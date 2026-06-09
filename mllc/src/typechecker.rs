use std::collections::HashMap;
use crate::ast::*;
use crate::tir::*;
use crate::types::*;

/// Type environment: maps names to type schemes
#[derive(Debug, Clone)]
pub struct TypeEnv {
    bindings: HashMap<String, Scheme>,
}

impl TypeEnv {
    pub fn new() -> Self {
        TypeEnv { bindings: HashMap::new() }
    }

    pub fn insert(&mut self, name: String, scheme: Scheme) {
        self.bindings.insert(name, scheme);
    }

    pub fn lookup(&self, name: &str) -> Option<&Scheme> {
        self.bindings.get(name)
    }

    pub fn apply_subst(&self, subst: &Subst) -> TypeEnv {
        TypeEnv {
            bindings: self.bindings.iter()
                .map(|(k, v)| (k.clone(), v.apply_subst(subst)))
                .collect(),
        }
    }

    pub fn free_vars(&self) -> Vec<TyVar> {
        let mut vars = Vec::new();
        for scheme in self.bindings.values() {
            for v in scheme.free_vars() {
                if !vars.contains(&v) {
                    vars.push(v);
                }
            }
        }
        vars
    }
}

/// Constructor info
#[derive(Debug, Clone)]
pub struct ConInfo {
    pub type_name: String,
    pub variant_index: usize,
    pub total_variants: usize,
    pub field_types: Vec<Ty>,
    pub type_vars: Vec<TyVar>,
    pub result_type: Ty,
}

/// Typeclass info
#[derive(Debug, Clone)]
pub struct ClassInfo {
    pub name: String,
    pub type_var: String,
    /// Method name -> method type (with type_var as placeholder)
    pub methods: Vec<(String, Ty)>,
}

/// Instance info
#[derive(Debug, Clone)]
pub struct InstanceInfo {
    pub class_name: String,
    pub target_type: Ty,
    /// Method name -> mangled function name
    pub method_fns: HashMap<String, String>,
}

/// The type checker — validates types and produces typed IR
pub struct Checker {
    env: TypeEnv,
    next_var: u32,
    constructors: HashMap<String, ConInfo>,
    pub errors: Vec<TypeError>,
    current_fn: Option<String>,
    /// Registered typeclasses
    classes: HashMap<String, ClassInfo>,
    /// Registered instances: (class_name, type_string) -> InstanceInfo
    instances: HashMap<(String, String), InstanceInfo>,
    /// Record field accessors: field_name -> (type_name, lua_index)
    pub record_fields: HashMap<String, (String, usize)>,
}

impl Checker {
    pub fn new() -> Self {
        let mut checker = Checker {
            env: TypeEnv::new(),
            next_var: 0,
            constructors: HashMap::new(),
            errors: Vec::new(),
            current_fn: None,
            classes: HashMap::new(),
            instances: HashMap::new(),
            record_fields: HashMap::new(),
        };
        checker.init_prelude();
        checker
    }

    fn fresh_var(&mut self, prefix: &str) -> Ty {
        let id = self.next_var;
        self.next_var += 1;
        Ty::Var(TyVar { name: format!("{}{}", prefix, id), id })
    }

    fn fresh_tyvar(&mut self, prefix: &str) -> TyVar {
        let id = self.next_var;
        self.next_var += 1;
        TyVar { name: format!("{}{}", prefix, id), id }
    }

    fn instantiate(&mut self, scheme: &Scheme) -> Ty {
        let mut map = HashMap::new();
        for v in &scheme.vars {
            if let Ty::Var(fresh) = self.fresh_var("_i") {
                map.insert(v.clone(), Ty::Var(fresh));
            }
        }
        scheme.ty.apply_subst(&Subst::from_map(map))
    }

    fn generalize(&self, env: &TypeEnv, ty: &Ty) -> Scheme {
        let env_vars = env.free_vars();
        let vars: Vec<TyVar> = ty.free_vars().into_iter()
            .filter(|v| !env_vars.contains(v))
            .collect();
        Scheme { vars, ty: ty.clone() }
    }

    fn ast_type_to_ty(&mut self, ast_ty: &Type) -> Ty {
        match ast_ty {
            Type::Con(name) => Ty::Con(name.clone()),
            Type::Var(name) => Ty::Var(TyVar { name: name.clone(), id: u32::MAX }),
            Type::Arrow(a, b) => Ty::arrow(self.ast_type_to_ty(a), self.ast_type_to_ty(b)),
            Type::App(f, a) => Ty::app(self.ast_type_to_ty(f), self.ast_type_to_ty(a)),
            Type::List(a) => Ty::list(self.ast_type_to_ty(a)),
            Type::IO(a) => Ty::io(self.ast_type_to_ty(a)),
            Type::ScopedLuaIO { scope_var, inner } => {
                let sv = TyVar { name: scope_var.clone(), id: u32::MAX };
                Ty::lua_io(sv, self.ast_type_to_ty(inner))
            }
            Type::Forall { var, inner } => {
                let tv = TyVar { name: var.clone(), id: u32::MAX };
                Ty::Forall(tv, Box::new(self.ast_type_to_ty(inner)))
            }
            Type::Unit => Ty::Unit,
            Type::Paren(inner) => self.ast_type_to_ty(inner),
            Type::Constrained { ty, .. } => self.ast_type_to_ty(ty),
            // LuaPure "name" T  reduces to  T
            Type::LuaPure { result, .. } => self.ast_type_to_ty(result),
            // LuaIO "name" T  reduces to  IO T
            Type::LuaIO { result, .. } => Ty::io(self.ast_type_to_ty(result)),
        }
    }

    fn freshen_sig_type(&mut self, ty: &Ty) -> Ty {
        // Strip forall and bind scope variables as rigid
        let inner = match ty {
            Ty::Forall(v, inner) => {
                // The forall-bound variable gets a fresh rigid binding
                // but stays rigid (can't unify with other types)
                let fresh = self.fresh_tyvar(&v.name);
                let subst = Subst::singleton(v.clone(), Ty::Var(fresh));
                return self.freshen_sig_type(&inner.apply_subst(&subst));
            }
            other => other,
        };
        let vars = inner.free_vars();
        let mut map = HashMap::new();
        for v in &vars {
            if v.id == u32::MAX {
                map.insert(v.clone(), Ty::Var(self.fresh_tyvar(&v.name)));
            }
        }
        inner.apply_subst(&Subst::from_map(map))
    }

    fn push_error_ctx(&mut self, kind: TypeErrorKind, ctx: String) {
        self.errors.push(TypeError { kind, context: Some(ctx), span: None });
    }

    fn push_error_span(&mut self, kind: TypeErrorKind, ctx: String, span: Span) {
        self.errors.push(TypeError { kind, context: Some(ctx), span: Some(span) });
    }

    fn literal_type(&self, lit: &Literal) -> Ty {
        match lit {
            Literal::Integer(_) => Ty::Con("Integer".into()),
            Literal::Number(_) => Ty::Con("Number".into()),
            Literal::Str(_) => Ty::Con("String".into()),
            Literal::Bool(_) => Ty::Con("Bool".into()),
        }
    }

    fn convert_literal(lit: &Literal) -> TLiteral {
        match lit {
            Literal::Integer(n) => TLiteral::Integer(*n),
            Literal::Number(n) => TLiteral::Number(*n),
            Literal::Str(s) => TLiteral::Str(s.clone()),
            Literal::Bool(b) => TLiteral::Bool(*b),
        }
    }

    // --- Prelude ---

    fn init_prelude(&mut self) {
        let a = TyVar { name: "a".into(), id: u32::MAX };
        let b = TyVar { name: "b".into(), id: u32::MAX };
        let c = TyVar { name: "c".into(), id: u32::MAX };
        let ta = Ty::Var(a.clone());
        let tb = Ty::Var(b.clone());
        let tc = Ty::Var(c.clone());

        let entries: Vec<(&str, Vec<TyVar>, Ty)> = vec![
            ("putStrLn", vec![], Ty::arrow(Ty::Con("String".into()), Ty::io(Ty::Unit))),
            ("print", vec![], Ty::arrow(Ty::Con("String".into()), Ty::io(Ty::Unit))),
            ("show", vec![a.clone()], Ty::arrow(ta.clone(), Ty::Con("String".into()))),
            ("++", vec![], Ty::fun(&[Ty::Con("String".into()), Ty::Con("String".into())], Ty::Con("String".into()))),
            ("$", vec![a.clone(), b.clone()], Ty::fun(&[Ty::arrow(ta.clone(), tb.clone()), ta.clone()], tb.clone())),
            (".", vec![a.clone(), b.clone(), c.clone()], Ty::fun(&[Ty::arrow(tb.clone(), tc.clone()), Ty::arrow(ta.clone(), tb.clone()), ta.clone()], tc.clone())),
            ("id", vec![a.clone()], Ty::arrow(ta.clone(), ta.clone())),
            ("const", vec![a.clone(), b.clone()], Ty::fun(&[ta.clone(), tb.clone()], ta.clone())),
            ("flip", vec![a.clone(), b.clone(), c.clone()], Ty::fun(&[Ty::fun(&[ta.clone(), tb.clone()], tc.clone()), tb.clone(), ta.clone()], tc.clone())),
            ("not", vec![], Ty::arrow(Ty::Con("Bool".into()), Ty::Con("Bool".into()))),
            ("error", vec![a.clone()], Ty::arrow(Ty::Con("String".into()), ta.clone())),
            ("sqrt", vec![], Ty::arrow(Ty::Con("Number".into()), Ty::Con("Number".into()))),
            ("otherwise", vec![], Ty::Con("Bool".into())),
        ];
        for (name, vars, ty) in entries {
            self.env.insert(name.into(), Scheme { vars, ty });
        }
        for name in &["max", "min"] {
            self.env.insert(name.to_string(), Scheme { vars: vec![a.clone()], ty: Ty::fun(&[ta.clone(), ta.clone()], ta.clone()) });
        }
        for op in &["+", "-", "*", "/"] {
            self.env.insert(op.to_string(), Scheme { vars: vec![a.clone()], ty: Ty::fun(&[ta.clone(), ta.clone()], ta.clone()) });
        }
        for op in &["==", "/=", "<", ">", "<=", ">="] {
            self.env.insert(op.to_string(), Scheme { vars: vec![a.clone()], ty: Ty::fun(&[ta.clone(), ta.clone()], Ty::Con("Bool".into())) });
        }
        for op in &["&&", "||"] {
            self.env.insert(op.to_string(), Scheme { vars: vec![], ty: Ty::fun(&[Ty::Con("Bool".into()), Ty::Con("Bool".into())], Ty::Con("Bool".into())) });
        }
        for name in &["mod", "div"] {
            self.env.insert(name.to_string(), Scheme { vars: vec![], ty: Ty::fun(&[Ty::Con("Integer".into()), Ty::Con("Integer".into())], Ty::Con("Integer".into())) });
        }
        self.env.insert("map".into(), Scheme { vars: vec![a.clone(), b.clone()], ty: Ty::fun(&[Ty::arrow(ta.clone(), tb.clone()), Ty::list(ta.clone())], Ty::list(tb.clone())) });
        self.env.insert("filter".into(), Scheme { vars: vec![a.clone(), b.clone()], ty: Ty::fun(&[Ty::arrow(ta.clone(), Ty::Con("Bool".into())), Ty::list(ta.clone())], Ty::list(ta.clone())) });
        self.env.insert("foldl".into(), Scheme { vars: vec![a.clone(), b.clone()], ty: Ty::fun(&[Ty::fun(&[tb.clone(), ta.clone()], tb.clone()), tb.clone(), Ty::list(ta.clone())], tb.clone()) });
        self.env.insert("foldr".into(), Scheme { vars: vec![a.clone(), b.clone()], ty: Ty::fun(&[Ty::fun(&[ta.clone(), tb.clone()], tb.clone()), tb.clone(), Ty::list(ta.clone())], tb.clone()) });

        // Maybe
        self.constructors.insert("Just".into(), ConInfo { type_name: "Maybe".into(), variant_index: 1, total_variants: 2, field_types: vec![ta.clone()], type_vars: vec![a.clone()], result_type: Ty::app(Ty::Con("Maybe".into()), ta.clone()) });
        self.constructors.insert("Nothing".into(), ConInfo { type_name: "Maybe".into(), variant_index: 2, total_variants: 2, field_types: vec![], type_vars: vec![a.clone()], result_type: Ty::app(Ty::Con("Maybe".into()), ta.clone()) });
        self.env.insert("Just".into(), Scheme { vars: vec![a.clone()], ty: Ty::arrow(ta.clone(), Ty::app(Ty::Con("Maybe".into()), ta.clone())) });
        self.env.insert("Nothing".into(), Scheme { vars: vec![a.clone()], ty: Ty::app(Ty::Con("Maybe".into()), ta.clone()) });
        self.env.insert("True".into(), Scheme::mono(Ty::Con("Bool".into())));
        self.env.insert("False".into(), Scheme::mono(Ty::Con("Bool".into())));

        // List constructors
        self.constructors.insert(":".into(), ConInfo {
            type_name: "[]".into(), variant_index: 1, total_variants: 2,
            field_types: vec![ta.clone(), Ty::list(ta.clone())],
            type_vars: vec![a.clone()],
            result_type: Ty::list(ta.clone()),
        });
        self.constructors.insert("[]".into(), ConInfo {
            type_name: "[]".into(), variant_index: 2, total_variants: 2,
            field_types: vec![],
            type_vars: vec![a.clone()],
            result_type: Ty::list(ta.clone()),
        });
        // (:) :: a -> [a] -> [a]
        self.env.insert(":".into(), Scheme {
            vars: vec![a.clone()],
            ty: Ty::fun(&[ta.clone(), Ty::list(ta.clone())], Ty::list(ta.clone())),
        });
        // [] :: [a]
        self.env.insert("[]".into(), Scheme {
            vars: vec![a.clone()],
            ty: Ty::list(ta.clone()),
        });

        // head :: [a] -> a
        self.env.insert("head".into(), Scheme {
            vars: vec![a.clone()],
            ty: Ty::arrow(Ty::list(ta.clone()), ta.clone()),
        });
        // tail :: [a] -> [a]
        self.env.insert("tail".into(), Scheme {
            vars: vec![a.clone()],
            ty: Ty::arrow(Ty::list(ta.clone()), Ty::list(ta.clone())),
        });
        // take :: Integer -> [a] -> [a]
        self.env.insert("take".into(), Scheme {
            vars: vec![a.clone()],
            ty: Ty::fun(&[Ty::Con("Integer".into()), Ty::list(ta.clone())], Ty::list(ta.clone())),
        });
        // zipWith :: (a -> b -> c) -> [a] -> [b] -> [c]
        self.env.insert("zipWith".into(), Scheme {
            vars: vec![a.clone(), b.clone(), c.clone()],
            ty: Ty::fun(&[
                Ty::fun(&[ta.clone(), tb.clone()], tc.clone()),
                Ty::list(ta.clone()),
                Ty::list(tb.clone()),
            ], Ty::list(tc.clone())),
        });
        // length :: [a] -> Integer
        self.env.insert("length".into(), Scheme {
            vars: vec![a.clone()],
            ty: Ty::arrow(Ty::list(ta.clone()), Ty::Con("Integer".into())),
        });
        // reverse :: [a] -> [a]
        self.env.insert("reverse".into(), Scheme {
            vars: vec![a.clone()],
            ty: Ty::arrow(Ty::list(ta.clone()), Ty::list(ta.clone())),
        });

        // LuaFunction and engage
        let s = TyVar { name: "s".into(), id: u32::MAX };
        let ts = Ty::Var(s.clone());

        // LuaFunction is just an opaque Con type — the scope var is
        // attached when it appears in a type signature as LuaFunction s
        // (handled by ast_type_to_ty via type application)

        // liftIO :: IO a -> LuaIO s a
        self.env.insert("liftIO".into(), Scheme {
            vars: vec![a.clone(), s.clone()],
            ty: Ty::arrow(Ty::io(ta.clone()), Ty::lua_io(s.clone(), ta.clone())),
        });

        // engage :: LuaFunction s -> a
        // (the type annotation at the call site determines a)
        // At runtime, engage is the identity — the LuaFunction is
        // already a Lua function, engage just satisfies the type system.
        self.env.insert("engage".into(), Scheme {
            vars: vec![a.clone(), s.clone()],
            ty: Ty::arrow(
                Ty::app(Ty::Con("LuaFunction".into()), Ty::Var(s.clone())),
                ta.clone(),
            ),
        });
    }

    // --- Data types ---

    fn register_data_type(&mut self, name: &str, type_vars: &[String], constructors: &[Constructor]) {
        let tvars: Vec<TyVar> = type_vars.iter()
            .map(|n| TyVar { name: n.clone(), id: u32::MAX })
            .collect();
        let result_type = tvars.iter().fold(Ty::Con(name.to_string()), |acc, tv| Ty::app(acc, Ty::Var(tv.clone())));

        for (i, con) in constructors.iter().enumerate() {
            let field_types: Vec<Ty> = match &con.fields {
                ConstructorFields::Positional(types) => types.iter().map(|t| self.ast_type_to_ty(t)).collect(),
                ConstructorFields::Named(fields) => fields.iter().map(|(_, t)| self.ast_type_to_ty(t)).collect(),
            };

            let con_type = if field_types.is_empty() { result_type.clone() } else { Ty::fun(&field_types, result_type.clone()) };

            self.constructors.insert(con.name.clone(), ConInfo {
                type_name: name.to_string(), variant_index: i + 1, total_variants: constructors.len(),
                field_types: field_types.clone(), type_vars: tvars.clone(), result_type: result_type.clone(),
            });
            self.env.insert(con.name.clone(), Scheme { vars: tvars.clone(), ty: con_type });

            // Register record field accessors
            if let ConstructorFields::Named(fields) = &con.fields {
                for (fi, (field_name, field_ast_ty)) in fields.iter().enumerate() {
                    let field_ty = self.ast_type_to_ty(field_ast_ty);
                    // accessor :: DataType -> FieldType
                    let accessor_ty = Ty::arrow(result_type.clone(), field_ty);
                    self.env.insert(field_name.clone(), Scheme {
                        vars: tvars.clone(),
                        ty: accessor_ty,
                    });
                    // Store field index for codegen
                    let index = if constructors.len() == 1 { fi + 1 } else { fi + 2 };
                    self.record_fields.insert(field_name.clone(), (name.to_string(), index));
                }
            }
        }
    }

    fn convert_data_def(&mut self, name: &str, type_vars: &[String], constructors: &[Constructor]) -> TDataDef {
        TDataDef {
            name: name.to_string(),
            type_vars: type_vars.to_vec(),
            constructors: constructors.iter().map(|c| {
                TConstructor {
                    name: c.name.clone(),
                    fields: match &c.fields {
                        ConstructorFields::Positional(types) =>
                            TConFields::Positional(types.iter().map(|t| self.ast_type_to_ty(t)).collect()),
                        ConstructorFields::Named(fields) =>
                            TConFields::Named(fields.iter().map(|(n, t)| (n.clone(), self.ast_type_to_ty(t))).collect()),
                    },
                }
            }).collect(),
        }
    }

    // --- Module checking (produces TIR) ---

    pub fn check_module(&mut self, module: &Module) -> TModule {
        // Pass 1: register data types
        for decl in &module.decls {
            if let Decl::DataDef { name, type_vars, constructors, .. } = decl {
                self.register_data_type(name, type_vars, constructors);
            }
        }

        // Pass 2: register typeclass declarations
        for decl in &module.decls {
            if let Decl::ClassDecl { name, type_var, methods } = decl {
                self.register_class(name, type_var, methods);
            }
        }

        // Pass 3: collect type signatures and FFI info
        let mut sigs: HashMap<String, Ty> = HashMap::new();
        let mut ffi_info: HashMap<String, (String, bool)> = HashMap::new(); // name -> (lua_name, is_io)
        for decl in &module.decls {
            if let Decl::TypeSig { name, ty } = decl {
                // Extract FFI info before reducing the type
                if let Some(info) = extract_ffi_info(ty) {
                    ffi_info.insert(name.clone(), info);
                }
                sigs.insert(name.clone(), self.ast_type_to_ty(ty));
            }
        }

        // Collect names that have function bodies
        let mut defined_fns: std::collections::HashSet<String> = std::collections::HashSet::new();
        for decl in &module.decls {
            if let Decl::FunDef { name, .. } = decl {
                defined_fns.insert(name.clone());
            }
        }

        // Pass 4: register and check instance declarations
        let mut instance_fns = Vec::new();
        for decl in &module.decls {
            if let Decl::InstanceDecl { class_name, target_type, methods } = decl {
                let ifns = self.check_instance(class_name, target_type, methods);
                instance_fns.extend(ifns);
            }
        }

        // Pass 5: generate FFI functions (type sigs with LuaPure/LuaIO and no body)
        let mut data_defs = Vec::new();
        let mut functions = Vec::new();
        let mut has_main = false;

        for (name, (lua_name, is_io)) in &ffi_info {
            if !defined_fns.contains(name) {
                if let Some(ty) = sigs.get(name) {
                    let ffi_fn = self.generate_ffi_function(name, lua_name, *is_io, ty);
                    functions.push(ffi_fn);
                    // Register in env
                    let scheme = self.generalize(&self.env.clone(), ty);
                    self.env.insert(name.clone(), scheme);
                }
            }
        }

        // Pass 6: collect exports and check function definitions
        let mut exports = Vec::new();
        for decl in &module.decls {
            match decl {
                Decl::DataDef { name, type_vars, constructors, deriving } => {
                    data_defs.push(self.convert_data_def(name, type_vars, constructors));
                    for class in deriving {
                        let derived = self.derive_instance(class, name, type_vars, constructors);
                        instance_fns.extend(derived);
                    }
                }
                Decl::FunDef { name, clauses } => {
                    if name == "main" { has_main = true; }
                    if let Some(declared_ty) = sigs.get(name) {
                        if let Some(tfun) = self.check_function(name, clauses, declared_ty) {
                            functions.push(tfun);
                        }
                    } else {
                        self.push_error_ctx(
                            TypeErrorKind::Other(format!("Missing type signature for '{}'", name)),
                            format!("definition of '{}'", name),
                        );
                    }
                }
                Decl::ExportSig { name, .. } => {
                    exports.push(name.clone());
                }
                _ => {}
            }
        }

        let record_accessors: Vec<(String, usize)> = self.record_fields.iter()
            .map(|(name, (_, idx))| (name.clone(), *idx))
            .collect();

        TModule { data_defs, functions, instance_fns, has_main, exports, record_accessors }
    }

    // --- Typeclass handling ---

    fn register_class(&mut self, name: &str, type_var: &str, methods: &[ClassMethod]) {
        let tv = TyVar { name: type_var.to_string(), id: u32::MAX };
        let mut method_types = Vec::new();

        for method in methods {
            let ty = self.ast_type_to_ty(&method.ty);
            method_types.push((method.name.clone(), ty.clone()));

            // Register class method in env as polymorphic
            // e.g., show :: a -> String (with Show constraint, which we ignore for now)
            self.env.insert(method.name.clone(), Scheme {
                vars: vec![tv.clone()],
                ty: ty,
            });
        }

        self.classes.insert(name.to_string(), ClassInfo {
            name: name.to_string(),
            type_var: type_var.to_string(),
            methods: method_types,
        });
    }

    fn check_instance(
        &mut self,
        class_name: &str,
        target_type: &Type,
        methods: &[InstanceMethod],
    ) -> Vec<TFunction> {
        let target_ty = self.ast_type_to_ty(target_type);
        let ty_str = format!("{}", target_ty);

        let class_info = match self.classes.get(class_name) {
            Some(ci) => ci.clone(),
            None => {
                self.push_error_ctx(
                    TypeErrorKind::Other(format!("Unknown typeclass '{}'", class_name)),
                    format!("instance {} {}", class_name, ty_str),
                );
                return vec![];
            }
        };

        let mut instance_info = InstanceInfo {
            class_name: class_name.to_string(),
            target_type: target_ty.clone(),
            method_fns: HashMap::new(),
        };

        let mut result_fns = Vec::new();

        for method_def in methods {
            // Find the class method's type
            let class_method_ty = class_info.methods.iter()
                .find(|(n, _)| n == &method_def.name)
                .map(|(_, ty)| ty.clone());

            let method_ty = match class_method_ty {
                Some(ty) => {
                    // Substitute the class type variable with the target type
                    let tv = TyVar { name: class_info.type_var.clone(), id: u32::MAX };
                    let subst = Subst::singleton(tv, target_ty.clone());
                    ty.apply_subst(&subst)
                }
                None => {
                    self.push_error_ctx(
                        TypeErrorKind::Other(format!("'{}' is not a method of class '{}'",
                            method_def.name, class_name)),
                        format!("instance {} {}", class_name, ty_str),
                    );
                    continue;
                }
            };

            // Generate mangled name: show_Integer, show_Bool, etc.
            let mangled_name = format!("{}_{}", method_def.name, ty_str);
            instance_info.method_fns.insert(method_def.name.clone(), mangled_name.clone());

            // Type-check the instance method against the specialized type
            if let Some(tfun) = self.check_function(&mangled_name, &method_def.clauses, &method_ty) {
                result_fns.push(tfun);
            }
        }

        self.instances.insert(
            (class_name.to_string(), ty_str),
            instance_info,
        );

        result_fns
    }

    /// Look up the instance method for a given class method + concrete type
    pub fn resolve_method(&self, method_name: &str, concrete_ty: &Ty) -> Option<String> {
        for class_info in self.classes.values() {
            if class_info.methods.iter().any(|(n, _)| n == method_name) {
                let ty_str = format!("{}", concrete_ty);
                let key = (class_info.name.clone(), ty_str);
                if let Some(inst) = self.instances.get(&key) {
                    return inst.method_fns.get(method_name).cloned();
                }
            }
        }
        None
    }

    /// Expose instances for the monomorphizer
    pub fn get_instances(&self) -> &HashMap<(String, String), InstanceInfo> {
        &self.instances
    }

    // --- Deriving ---

    fn derive_instance(
        &mut self,
        class: &str,
        type_name: &str,
        type_vars: &[String],
        constructors: &[Constructor],
    ) -> Vec<TFunction> {
        match class {
            "Show" => self.derive_show(type_name, type_vars, constructors),
            "Eq" => self.derive_eq(type_name, type_vars, constructors),
            other => {
                self.push_error_ctx(
                    TypeErrorKind::Other(format!("Cannot derive '{}' — only Show and Eq are supported", other)),
                    format!("data {}", type_name),
                );
                vec![]
            }
        }
    }

    /// Generate `show` for a data type.
    /// For each constructor, generates a clause that produces "Constructor field1 field2 ...".
    fn derive_show(
        &mut self,
        type_name: &str,
        type_vars: &[String],
        constructors: &[Constructor],
    ) -> Vec<TFunction> {
        let tvars: Vec<TyVar> = type_vars.iter()
            .map(|n| TyVar { name: n.clone(), id: u32::MAX })
            .collect();
        let result_type = tvars.iter().fold(
            Ty::Con(type_name.to_string()),
            |acc, tv| Ty::app(acc, Ty::Var(tv.clone())),
        );

        let mangled = format!("show_{}", type_name);
        let fn_ty = Ty::arrow(result_type.clone(), Ty::Con("String".into()));

        let mut clauses = Vec::new();
        for con in constructors {
            let field_count = match &con.fields {
                ConstructorFields::Positional(fs) => fs.len(),
                ConstructorFields::Named(fs) => fs.len(),
            };

            // Build patterns: Con p0 p1 p2 ...
            let param_names: Vec<String> = (0..field_count)
                .map(|i| format!("_s{}", i))
                .collect();

            let con_info = self.constructors.get(&con.name).cloned();
            let field_tys: Vec<Ty> = con_info.as_ref()
                .map(|ci| ci.field_types.clone())
                .unwrap_or_default();

            let patterns = vec![
                TPattern::Constructor {
                    name: con.name.clone(),
                    args: param_names.iter().enumerate().map(|(i, n)| {
                        let ty = field_tys.get(i).cloned().unwrap_or(Ty::Unit);
                        TPattern::Var(n.clone(), ty)
                    }).collect(),
                }
            ];

            // Build body: "ConName" ++ " " ++ show p0 ++ " " ++ show p1 ...
            let mut body = TExpr::new(
                TExprKind::Lit(TLiteral::Str(con.name.clone())),
                Ty::Con("String".into()),
            );

            for (i, pname) in param_names.iter().enumerate() {
                let field_ty = field_tys.get(i).cloned().unwrap_or(Ty::Unit);

                // " "
                let space = TExpr::new(
                    TExprKind::Lit(TLiteral::Str(" ".into())),
                    Ty::Con("String".into()),
                );
                // concat body ++ " "
                body = TExpr::new(
                    TExprKind::InfixApp {
                        op: "++".into(),
                        lhs: Box::new(body),
                        rhs: Box::new(space),
                    },
                    Ty::Con("String".into()),
                );

                // show field_i
                let field_shown = TExpr::new(
                    TExprKind::App(
                        Box::new(TExpr::new(
                            TExprKind::Var("show".into()),
                            Ty::arrow(field_ty.clone(), Ty::Con("String".into())),
                        )),
                        Box::new(TExpr::new(
                            TExprKind::Var(pname.clone()),
                            field_ty,
                        )),
                    ),
                    Ty::Con("String".into()),
                );

                body = TExpr::new(
                    TExprKind::InfixApp {
                        op: "++".into(),
                        lhs: Box::new(body),
                        rhs: Box::new(field_shown),
                    },
                    Ty::Con("String".into()),
                );
            }

            clauses.push(TClause {
                patterns,
                guards: vec![],
                body,
                where_binds: vec![],
            });
        }

        // Register the instance
        let mut method_fns = HashMap::new();
        method_fns.insert("show".to_string(), mangled.clone());
        self.instances.insert(
            ("Show".to_string(), type_name.to_string()),
            InstanceInfo {
                class_name: "Show".to_string(),
                target_type: result_type.clone(),
                method_fns,
            },
        );

        vec![TFunction {
            name: mangled,
            ty: fn_ty,
            clauses,
            specialized: false,
        }]
    }

    /// Generate `==` for a data type.
    /// Two values are equal if they have the same constructor and all fields are equal.
    fn derive_eq(
        &mut self,
        type_name: &str,
        type_vars: &[String],
        constructors: &[Constructor],
    ) -> Vec<TFunction> {
        let tvars: Vec<TyVar> = type_vars.iter()
            .map(|n| TyVar { name: n.clone(), id: u32::MAX })
            .collect();
        let result_type = tvars.iter().fold(
            Ty::Con(type_name.to_string()),
            |acc, tv| Ty::app(acc, Ty::Var(tv.clone())),
        );

        let mangled = format!("eq_{}", type_name);
        let fn_ty = Ty::fun(&[result_type.clone(), result_type.clone()], Ty::Con("Bool".into()));

        let mut clauses = Vec::new();

        for con in constructors {
            let field_count = match &con.fields {
                ConstructorFields::Positional(fs) => fs.len(),
                ConstructorFields::Named(fs) => fs.len(),
            };

            let con_info = self.constructors.get(&con.name).cloned();
            let field_tys: Vec<Ty> = con_info.as_ref()
                .map(|ci| ci.field_types.clone())
                .unwrap_or_default();

            let a_names: Vec<String> = (0..field_count).map(|i| format!("_a{}", i)).collect();
            let b_names: Vec<String> = (0..field_count).map(|i| format!("_b{}", i)).collect();

            let pat_a = TPattern::Constructor {
                name: con.name.clone(),
                args: a_names.iter().enumerate().map(|(i, n)| {
                    let ty = field_tys.get(i).cloned().unwrap_or(Ty::Unit);
                    TPattern::Var(n.clone(), ty)
                }).collect(),
            };
            let pat_b = TPattern::Constructor {
                name: con.name.clone(),
                args: b_names.iter().enumerate().map(|(i, n)| {
                    let ty = field_tys.get(i).cloned().unwrap_or(Ty::Unit);
                    TPattern::Var(n.clone(), ty)
                }).collect(),
            };

            // Build body: a0 == b0 && a1 == b1 && ...
            let mut body = TExpr::new(
                TExprKind::Lit(TLiteral::Bool(true)),
                Ty::Con("Bool".into()),
            );

            for i in (0..field_count).rev() {
                let field_ty = field_tys.get(i).cloned().unwrap_or(Ty::Unit);
                let eq_expr = TExpr::new(
                    TExprKind::InfixApp {
                        op: "==".into(),
                        lhs: Box::new(TExpr::new(
                            TExprKind::Var(a_names[i].clone()),
                            field_ty.clone(),
                        )),
                        rhs: Box::new(TExpr::new(
                            TExprKind::Var(b_names[i].clone()),
                            field_ty,
                        )),
                    },
                    Ty::Con("Bool".into()),
                );
                body = TExpr::new(
                    TExprKind::InfixApp {
                        op: "&&".into(),
                        lhs: Box::new(eq_expr),
                        rhs: Box::new(body),
                    },
                    Ty::Con("Bool".into()),
                );
            }

            clauses.push(TClause {
                patterns: vec![pat_a, pat_b],
                guards: vec![],
                body,
                where_binds: vec![],
            });
        }

        // Add catch-all clause for different constructors: _ _ = False
        if constructors.len() > 1 {
            clauses.push(TClause {
                patterns: vec![
                    TPattern::Wildcard,
                    TPattern::Wildcard,
                ],
                guards: vec![],
                body: TExpr::new(TExprKind::Lit(TLiteral::Bool(false)), Ty::Con("Bool".into())),
                where_binds: vec![],
            });
        }

        // Register the instance
        let mut method_fns = HashMap::new();
        method_fns.insert("==".to_string(), mangled.clone());
        self.instances.insert(
            ("Eq".to_string(), type_name.to_string()),
            InstanceInfo {
                class_name: "Eq".to_string(),
                target_type: result_type.clone(),
                method_fns,
            },
        );

        vec![TFunction {
            name: mangled,
            ty: fn_ty,
            clauses,
            specialized: false,
        }]
    }

    // --- Exhaustiveness checking ---

    /// Check if a list of patterns exhaustively covers a data type.
    /// Returns a list of missing constructor names, or empty if exhaustive.
    fn check_exhaustiveness(&self, patterns: &[&Pattern]) -> Vec<String> {
        // Collect constructor names, unwrapping parens, checking for catch-alls
        let mut seen_constructors: Vec<String> = Vec::new();
        let mut type_name: Option<String> = None;
        let mut has_literal = false;

        for p in patterns {
            self.collect_pattern_info(p, &mut seen_constructors, &mut type_name, &mut has_literal);
        }

        // If any pattern is a catch-all (variable/wildcard found), it's exhaustive
        if seen_constructors.contains(&"*".to_string()) { return vec![]; }

        // If we have literals, we can't check exhaustiveness
        if has_literal { return vec![]; }

        // If we have no constructors, nothing to check
        let type_name = match type_name {
            Some(t) => t,
            None => return vec![],
        };

        // Find all constructors for this type
        let all_constructors: Vec<String> = self.constructors.iter()
            .filter(|(_, info)| info.type_name == type_name)
            .map(|(name, _)| name.clone())
            .collect();

        // Return missing ones
        all_constructors.into_iter()
            .filter(|c| !seen_constructors.contains(c))
            .collect()
    }

    /// Recursively collect pattern info, unwrapping Paren wrappers.
    fn collect_pattern_info(
        &self,
        pattern: &Pattern,
        seen: &mut Vec<String>,
        type_name: &mut Option<String>,
        has_literal: &mut bool,
    ) {
        match pattern {
            Pattern::Var(_) | Pattern::Wildcard => {
                // Use a sentinel to indicate catch-all
                if !seen.contains(&"*".to_string()) {
                    seen.push("*".to_string());
                }
            }
            Pattern::Constructor { name, .. } => {
                if let Some(info) = self.constructors.get(name) {
                    *type_name = Some(info.type_name.clone());
                    if !seen.contains(name) {
                        seen.push(name.clone());
                    }
                }
            }
            Pattern::LitPat(_) => { *has_literal = true; }
            Pattern::Paren(inner) => {
                self.collect_pattern_info(inner, seen, type_name, has_literal);
            }
        }
    }

    // --- Function checking ---

    fn check_function(&mut self, name: &str, clauses: &[Clause], declared_ty: &Ty) -> Option<TFunction> {
        self.current_fn = Some(name.to_string());
        let fresh_ty = self.freshen_sig_type(declared_ty);

        // Add self for recursion
        let self_scheme = self.generalize(&self.env.clone(), &fresh_ty);
        self.env.insert(name.to_string(), self_scheme);

        let mut tclauses = Vec::new();

        for (clause_idx, clause) in clauses.iter().enumerate() {
            let clause_ctx = if clauses.len() > 1 {
                format!("clause {} of '{}'", clause_idx + 1, name)
            } else {
                format!("definition of '{}'", name)
            };

            match self.check_clause(clause, &fresh_ty, &clause_ctx) {
                Ok(tc) => tclauses.push(tc),
                Err(e) => { self.push_error_span(e, clause_ctx, clause.span); }
            }
        }

        // Check exhaustiveness of first argument patterns
        if !clauses.is_empty() && !clauses[0].patterns.is_empty() {
            let first_patterns: Vec<&Pattern> = clauses.iter()
                .map(|c| &c.patterns[0])
                .collect();
            let missing = self.check_exhaustiveness(&first_patterns);
            if !missing.is_empty() {
                self.push_error_span(
                    TypeErrorKind::NonExhaustive(format!(
                        "'{}': missing patterns for {}", name, missing.join(", ")
                    )),
                    format!("definition of '{}'", name),
                    clauses[0].span,
                );
            }
        }

        self.current_fn = None;

        if tclauses.is_empty() && !clauses.is_empty() {
            return None;
        }

        Some(TFunction {
            name: name.to_string(),
            ty: fresh_ty,
            clauses: tclauses,
            specialized: false,
        })
    }

    fn check_clause(&mut self, clause: &Clause, fun_ty: &Ty, ctx: &str) -> Result<TClause, TypeErrorKind> {
        let mut local_env = self.env.clone();
        let mut remaining_ty = fun_ty.clone();
        let mut subst = Subst::empty();
        let mut tpatterns = Vec::new();

        for pattern in &clause.patterns {
            match &remaining_ty {
                Ty::Arrow(arg_ty, ret_ty) => {
                    let arg_ty = arg_ty.apply_subst(&subst);
                    let (tp, pat_subst) = self.check_pattern(pattern, &arg_ty, &mut local_env)?;
                    subst = subst.compose(&pat_subst);
                    remaining_ty = *ret_ty.clone();
                    tpatterns.push(tp);
                }
                _ => return Err(TypeErrorKind::Other("Too many arguments".into())),
            }
        }

        let expected_ret = remaining_ty.apply_subst(&subst);

        let mut tguards = Vec::new();
        let tbody;

        if !clause.guards.is_empty() {
            for guard in &clause.guards {
                let (tcond, cond_ty, s1) = self.infer_expr(&guard.condition, &local_env)?;
                let s2 = unify(&cond_ty.apply_subst(&s1), &Ty::Con("Bool".into()))?;
                let combined = s1.compose(&s2);
                subst = subst.compose(&combined);
                let (tbody_g, body_s) = self.check_expr_typed(&guard.body, &expected_ret, &local_env)?;
                subst = subst.compose(&body_s);
                tguards.push(TGuard { condition: tcond, body: tbody_g });
            }
            tbody = TExpr::new(TExprKind::Var("undefined".into()), expected_ret);
        } else {
            let (tb, body_s) = self.check_expr_typed(&clause.body, &expected_ret, &local_env)?;
            subst = subst.compose(&body_s);
            tbody = tb;
        }

        let twhere = clause.where_binds.iter().map(|ld| {
            let (texpr, _, _) = self.infer_expr(&ld.body, &local_env).unwrap_or_else(|_| {
                (TExpr::new(TExprKind::Var("error".into()), Ty::Unit), Ty::Unit, Subst::empty())
            });
            TLocalDef {
                name: ld.name.clone(),
                patterns: vec![],
                body: texpr,
            }
        }).collect();

        // Apply the accumulated substitution to the entire clause
        let raw_clause = TClause {
            patterns: tpatterns,
            guards: tguards,
            body: tbody,
            where_binds: twhere,
        };
        Ok(raw_clause.apply_subst(&subst))
    }

    // --- Pattern checking (returns typed pattern) ---

    fn check_pattern(
        &mut self, pattern: &Pattern, expected: &Ty, env: &mut TypeEnv,
    ) -> Result<(TPattern, Subst), TypeErrorKind> {
        match pattern {
            Pattern::Var(name) => {
                env.insert(name.clone(), Scheme::mono(expected.clone()));
                Ok((TPattern::Var(name.clone(), expected.clone()), Subst::empty()))
            }
            Pattern::Wildcard => Ok((TPattern::Wildcard, Subst::empty())),
            Pattern::LitPat(lit) => {
                let lit_ty = self.literal_type(lit);
                let s = unify(expected, &lit_ty)?;
                Ok((TPattern::LitPat(Self::convert_literal(lit)), s))
            }
            Pattern::Constructor { name, args } => {
                let con_info = self.constructors.get(name)
                    .ok_or_else(|| TypeErrorKind::UnboundConstructor(name.clone()))?.clone();

                if args.len() != con_info.field_types.len() {
                    return Err(TypeErrorKind::PatternArgCount {
                        constructor: name.clone(), expected: con_info.field_types.len(), got: args.len(),
                    });
                }

                let mut tv_map = HashMap::new();
                for tv in &con_info.type_vars {
                    if let Ty::Var(fresh) = self.fresh_var("_p") {
                        tv_map.insert(tv.clone(), Ty::Var(fresh));
                    }
                }
                let tv_subst = Subst::from_map(tv_map);
                let result_ty = con_info.result_type.apply_subst(&tv_subst);
                let mut subst = unify(expected, &result_ty)?;

                let mut targs = Vec::new();
                for (arg_pat, field_ty) in args.iter().zip(&con_info.field_types) {
                    let expected_field = field_ty.apply_subst(&tv_subst).apply_subst(&subst);
                    let (tp, s) = self.check_pattern(arg_pat, &expected_field, env)?;
                    subst = subst.compose(&s);
                    targs.push(tp);
                }

                Ok((TPattern::Constructor { name: name.clone(), args: targs }, subst))
            }
            Pattern::Paren(inner) => self.check_pattern(inner, expected, env),
        }
    }

    // --- Expression inference (returns typed expr) ---

    fn infer_expr(&mut self, expr: &Expr, env: &TypeEnv) -> Result<(TExpr, Ty, Subst), TypeErrorKind> {
        match expr {
            Expr::Var(name) => {
                if let Some(scheme) = env.lookup(name) {
                    let ty = self.instantiate(scheme);
                    Ok((TExpr::new(TExprKind::Var(name.clone()), ty.clone()), ty, Subst::empty()))
                } else {
                    Err(TypeErrorKind::UnboundVariable(name.clone()))
                }
            }
            Expr::Con(name) => {
                if let Some(scheme) = env.lookup(name) {
                    let ty = self.instantiate(scheme);
                    Ok((TExpr::new(TExprKind::Con(name.clone()), ty.clone()), ty, Subst::empty()))
                } else {
                    Err(TypeErrorKind::UnboundConstructor(name.clone()))
                }
            }
            Expr::Lit(lit) => {
                let ty = self.literal_type(lit);
                Ok((TExpr::new(TExprKind::Lit(Self::convert_literal(lit)), ty.clone()), ty, Subst::empty()))
            }
            Expr::App(func, arg) => {
                let (tf, func_ty, s1) = self.infer_expr(func, env)?;
                let env2 = env.apply_subst(&s1);
                let (ta, arg_ty, s2) = self.infer_expr(arg, &env2)?;
                let ret_ty = self.fresh_var("_r");
                let func_ty = func_ty.apply_subst(&s2);
                let s3 = unify(&func_ty, &Ty::arrow(arg_ty, ret_ty.clone()))?;
                let final_ty = ret_ty.apply_subst(&s3);
                Ok((
                    TExpr::new(TExprKind::App(Box::new(tf), Box::new(ta)), final_ty.clone()),
                    final_ty,
                    s1.compose(&s2).compose(&s3),
                ))
            }
            Expr::InfixApp { op, lhs, rhs } => {
                // Desugar to App(App(op, lhs), rhs) for type inference
                let op_expr = if env.lookup(op).is_some() {
                    Expr::Var(op.clone())
                } else {
                    Expr::OpFunc(op.clone())
                };
                let desugared = Expr::App(
                    Box::new(Expr::App(Box::new(op_expr), Box::new(*lhs.clone()))),
                    Box::new(*rhs.clone()),
                );
                let (te, ty, subst) = self.infer_expr(&desugared, env)?;
                // Reconstruct as InfixApp in the TIR for codegen
                if let TExprKind::App(f, rhs_t) = te.kind {
                    if let TExprKind::App(_, lhs_t) = f.kind {
                        return Ok((
                            TExpr::new(TExprKind::InfixApp {
                                op: op.clone(), lhs: lhs_t, rhs: rhs_t,
                            }, ty.clone()),
                            ty, subst,
                        ));
                    }
                }
                // Fallback: just return the desugared form
                let (te2, ty2, subst2) = self.infer_expr(&desugared, env)?;
                Ok((te2, ty2, subst2))
            }
            Expr::Negate(inner) => {
                let (te, ty, s) = self.infer_expr(inner, env)?;
                Ok((TExpr::new(TExprKind::Negate(Box::new(te)), ty.clone()), ty, s))
            }
            Expr::Lambda { params, body } => {
                let mut local_env = env.clone();
                let mut param_info = Vec::new();
                for param in params {
                    let param_ty = self.fresh_var("_l");
                    if param != "_" {
                        local_env.insert(param.clone(), Scheme::mono(param_ty.clone()));
                    }
                    param_info.push((param.clone(), param_ty));
                }
                let (tbody, body_ty, subst) = self.infer_expr(body, &local_env)?;
                let func_ty = param_info.iter().rev().fold(body_ty, |acc, (_, pt)| {
                    Ty::arrow(pt.apply_subst(&subst), acc)
                });
                let typed_params: Vec<(String, Ty)> = param_info.iter()
                    .map(|(n, t)| (n.clone(), t.apply_subst(&subst)))
                    .collect();
                Ok((
                    TExpr::new(TExprKind::Lambda { params: typed_params, body: Box::new(tbody) }, func_ty.clone()),
                    func_ty, subst,
                ))
            }
            Expr::If { cond, then_branch, else_branch } => {
                let (tc, cond_ty, s1) = self.infer_expr(cond, env)?;
                let sb = unify(&cond_ty, &Ty::Con("Bool".into()))?;
                let s1 = s1.compose(&sb);
                let env2 = env.apply_subst(&s1);
                let (tt, then_ty, s2) = self.infer_expr(then_branch, &env2)?;
                let env3 = env2.apply_subst(&s2);
                let (te, else_ty, s3) = self.infer_expr(else_branch, &env3)?;
                let s4 = unify(&then_ty.apply_subst(&s3), &else_ty)?;
                let final_ty = then_ty.apply_subst(&s3).apply_subst(&s4);
                Ok((
                    TExpr::new(TExprKind::If {
                        cond: Box::new(tc), then_branch: Box::new(tt), else_branch: Box::new(te),
                    }, final_ty.clone()),
                    final_ty, s1.compose(&s2).compose(&s3).compose(&s4),
                ))
            }
            Expr::Case { scrutinee, branches } => {
                let (ts, scrut_ty, s1) = self.infer_expr(scrutinee, env)?;
                let result_ty = self.fresh_var("_c");
                let mut subst = s1;
                let mut tbranches = Vec::new();

                for branch in branches {
                    let mut branch_env = env.apply_subst(&subst);
                    let scrut_ty = scrut_ty.apply_subst(&subst);
                    let (tp, pat_subst) = self.check_pattern(&branch.pattern, &scrut_ty, &mut branch_env)?;
                    subst = subst.compose(&pat_subst);
                    let (tb, body_ty, body_subst) = self.infer_expr(&branch.body, &branch_env)?;
                    subst = subst.compose(&body_subst);
                    let s = unify(&result_ty.apply_subst(&subst), &body_ty)?;
                    subst = subst.compose(&s);
                    tbranches.push(TCaseBranch { pattern: tp, guards: vec![], body: tb });
                }

                // Check exhaustiveness of case patterns
                let case_patterns: Vec<&Pattern> = branches.iter()
                    .map(|b| &b.pattern)
                    .collect();
                let missing = self.check_exhaustiveness(&case_patterns);
                if !missing.is_empty() {
                    let fn_name = self.current_fn.clone().unwrap_or_else(|| "<expr>".into());
                    self.push_error_ctx(
                        TypeErrorKind::NonExhaustive(format!(
                            "case expression in '{}': missing patterns for {}",
                            fn_name, missing.join(", ")
                        )),
                        format!("definition of '{}'", fn_name),
                    );
                }

                let final_ty = result_ty.apply_subst(&subst);
                Ok((
                    TExpr::new(TExprKind::Case { scrutinee: Box::new(ts), branches: tbranches }, final_ty.clone()),
                    final_ty, subst,
                ))
            }
            Expr::Let { binds, body } => {
                let mut local_env = env.clone();
                let mut subst = Subst::empty();
                let mut tbinds = Vec::new();

                for bind in binds {
                    let (te, bind_ty, s) = self.infer_expr(&bind.body, &local_env)?;
                    subst = subst.compose(&s);
                    let gen_env = local_env.apply_subst(&subst);
                    let scheme = self.generalize(&gen_env, &bind_ty.apply_subst(&subst));
                    local_env = gen_env;
                    local_env.insert(bind.name.clone(), scheme);
                    tbinds.push(TLocalDef { name: bind.name.clone(), patterns: vec![], body: te });
                }

                let (tbody, body_ty, s) = self.infer_expr(body, &local_env)?;
                Ok((
                    TExpr::new(TExprKind::Let { binds: tbinds, body: Box::new(tbody) }, body_ty.clone()),
                    body_ty, subst.compose(&s),
                ))
            }
            Expr::Do(stmts) => self.infer_do_typed(stmts, env),
            Expr::Paren(inner) => {
                let (te, ty, s) = self.infer_expr(inner, env)?;
                Ok((TExpr::new(TExprKind::Paren(Box::new(te)), ty.clone()), ty, s))
            }
            Expr::OpFunc(op) => {
                if let Some(scheme) = env.lookup(op) {
                    let ty = self.instantiate(scheme);
                    Ok((TExpr::new(TExprKind::OpFunc(op.clone()), ty.clone()), ty, Subst::empty()))
                } else {
                    Err(TypeErrorKind::UnboundVariable(format!("({})", op)))
                }
            }
        }
    }

    fn check_expr_typed(&mut self, expr: &Expr, expected: &Ty, env: &TypeEnv) -> Result<(TExpr, Subst), TypeErrorKind> {
        let (te, inferred, subst) = self.infer_expr(expr, env)?;
        let s = unify(&inferred.apply_subst(&subst), &expected.apply_subst(&subst))?;
        let final_ty = inferred.apply_subst(&subst).apply_subst(&s);
        Ok((TExpr { kind: te.kind, ty: final_ty }, subst.compose(&s)))
    }

    fn infer_do_typed(&mut self, stmts: &[DoStmt], env: &TypeEnv) -> Result<(TExpr, Ty, Subst), TypeErrorKind> {
        let mut local_env = env.clone();
        let mut subst = Subst::empty();
        let mut last_ty = Ty::io(Ty::Unit);
        let mut tstmts = Vec::new();

        for (i, stmt) in stmts.iter().enumerate() {
            let is_last = i == stmts.len() - 1;
            match stmt {
                DoStmt::Bind { name, expr } => {
                    let (te, expr_ty, s) = self.infer_expr(expr, &local_env)?;
                    subst = subst.compose(&s);
                    let inner_ty = self.fresh_var("_d");
                    let resolved_ty = expr_ty.apply_subst(&subst);
                    // Try IO first, then LuaIO
                    let s2 = unify(&resolved_ty, &Ty::io(inner_ty.clone()))
                        .or_else(|_| {
                            let scope = self.fresh_var("_s");
                            if let Ty::Var(sv) = &scope {
                                unify(&resolved_ty, &Ty::lua_io(sv.clone(), inner_ty.clone()))
                            } else {
                                unify(&resolved_ty, &Ty::io(inner_ty.clone()))
                            }
                        })?;
                    subst = subst.compose(&s2);
                    let bound_ty = inner_ty.apply_subst(&subst);
                    local_env = local_env.apply_subst(&subst);
                    local_env.insert(name.clone(), Scheme::mono(bound_ty.clone()));
                    tstmts.push(TDoStmt::Bind { name: name.clone(), ty: bound_ty, expr: te });
                }
                DoStmt::DoLet { name, expr } => {
                    let (te, expr_ty, s) = self.infer_expr(expr, &local_env)?;
                    subst = subst.compose(&s);
                    let ty = expr_ty.apply_subst(&subst);
                    local_env = local_env.apply_subst(&subst);
                    local_env.insert(name.clone(), Scheme::mono(ty.clone()));
                    tstmts.push(TDoStmt::DoLet { name: name.clone(), ty: ty, expr: te });
                }
                DoStmt::Expr(expr) => {
                    let (te, expr_ty, s) = self.infer_expr(expr, &local_env)?;
                    subst = subst.compose(&s);
                    last_ty = expr_ty.apply_subst(&subst);
                    if !is_last {
                        let discard = self.fresh_var("_d");
                        let s2 = unify(&last_ty, &Ty::io(discard))?;
                        subst = subst.compose(&s2);
                    }
                    local_env = local_env.apply_subst(&subst);
                    tstmts.push(TDoStmt::Expr(te));
                }
            }
        }

        Ok((TExpr::new(TExprKind::Do(tstmts), last_ty.clone()), last_ty, subst))
    }

    /// Generate a TIR function for an FFI declaration.
    /// The function body calls the named Lua function directly.
    fn generate_ffi_function(&mut self, name: &str, lua_name: &str, is_io: bool, ty: &Ty) -> TFunction {
        // Count argument types from the function type
        let mut arg_types = Vec::new();
        let mut current = ty.clone();
        loop {
            match current {
                Ty::Arrow(a, b) => {
                    arg_types.push(*a);
                    current = *b;
                }
                _ => break,
            }
        }
        let ret_ty = current;

        // Generate parameter names and patterns
        let params: Vec<(String, Ty)> = arg_types.iter().enumerate()
            .map(|(i, t)| (format!("_ffi{}", i), t.clone()))
            .collect();

        let patterns: Vec<TPattern> = params.iter()
            .map(|(n, t)| TPattern::Var(n.clone(), t.clone()))
            .collect();

        // Build the call expression: lua_func(_ffi0, _ffi1, ...)
        // We use a special FFI call node
        let call_args: Vec<TExpr> = params.iter()
            .map(|(n, t)| TExpr::new(TExprKind::Var(n.clone()), t.clone()))
            .collect();

        let body = TExpr::new(
            TExprKind::SpecCall {
                original: name.to_string(),
                specialized: lua_name.to_string(),
                args: call_args,
            },
            ret_ty.clone(),
        );

        TFunction {
            name: name.to_string(),
            ty: ty.clone(),
            clauses: vec![TClause {
                patterns,
                guards: vec![],
                body,
                where_binds: vec![],
            }],
            specialized: false,
        }
    }
}

/// Extract FFI info from an AST type.
/// Walks through Arrow types to find LuaPure/LuaIO at the return position.
/// Returns (lua_function_name, is_io).
fn extract_ffi_info(ty: &Type) -> Option<(String, bool)> {
    match ty {
        Type::Arrow(_, b) => extract_ffi_info(b),
        Type::LuaPure { lua_name, .. } => Some((lua_name.clone(), false)),
        Type::LuaIO { lua_name, .. } => Some((lua_name.clone(), true)),
        Type::Paren(inner) => extract_ffi_info(inner),
        _ => None,
    }
}

