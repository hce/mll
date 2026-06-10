/// Monomorphization pass
///
/// Walks the typed IR and collects all concrete type instantiations
/// of polymorphic functions. For each unique instantiation, generates
/// a specialized copy with a mangled name and rewrites call sites.

use std::collections::{HashMap, HashSet};
use crate::tir::*;
use crate::typechecker::Checker;
use crate::types::Ty;

/// A specialization demand: function name + concrete type arguments
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct SpecKey {
    name: String,
    ty: String, // stringified type for hashing
}

pub struct Monomorphizer {
    /// Known polymorphic functions (name -> TFunction)
    poly_fns: HashMap<String, TFunction>,
    /// Set of prelude/built-in names (don't try to specialize these)
    builtins: HashSet<String>,
    /// Collected specializations: SpecKey -> mangled name
    specializations: HashMap<SpecKey, String>,
    /// Generated specialized functions
    generated: Vec<TFunction>,
    /// Counter for unique names
    counter: u32,
    /// Typeclass method -> set of class names it belongs to
    class_methods: HashSet<String>,
    /// Instance resolution: (method_name, type_string) -> mangled function name
    instance_methods: HashMap<(String, String), String>,
    /// Errors collected during monomorphization
    pub errors: Vec<String>,
}

impl Monomorphizer {
    pub fn new(checker: &Checker) -> Self {
        let mut builtins = HashSet::new();
        // Only mark as builtin functions that DON'T have user-defined instances
        for name in &[
            "putStrLn", "print", "++", "$", ".", "id", "const",
            "flip", "not", "error", "sqrt", "otherwise", "max", "min",
            "+", "-", "*", "/", "==", "/=", "<", ">", "<=", ">=",
            "&&", "||", "mod", "div", "map", "filter", "foldl", "foldr",
            "True", "False", "Just", "Nothing",
            ":", "[]", "head", "tail", "take", "zipWith", "length", "reverse",
            "engage", "liftIO",
            "hmEmpty", "hmInsert", "hmLookup", "hmDelete",
            "hmSize", "hmKeys", "hmValues", "hmMember",
        ] {
            builtins.insert(name.to_string());
        }

        // Collect class method names and instance resolutions from the checker
        let mut class_methods = HashSet::new();
        let mut instance_methods = HashMap::new();

        for ((_class_name, _ty_str), inst) in checker.get_instances() {
            for (method_name, mangled) in &inst.method_fns {
                class_methods.insert(method_name.clone());
                // Key: (method_name, concrete_type_string)
                let ty_str = format!("{}", inst.target_type);
                instance_methods.insert((method_name.clone(), ty_str), mangled.clone());
            }
        }

        // Class methods with instances should NOT be in builtins
        // (they need to be resolved to instance methods)
        for m in &class_methods {
            builtins.remove(m);
        }
        // But also remove "show" from builtins since it's commonly a class method
        builtins.remove("show");

        Monomorphizer {
            poly_fns: HashMap::new(),
            builtins,
            specializations: HashMap::new(),
            generated: Vec::new(),
            counter: 0,
            class_methods,
            instance_methods,
            errors: Vec::new(),
        }
    }

    pub fn run(&mut self, module: TModule) -> TModule {
        // Collect polymorphic user-defined functions
        for func in &module.functions {
            if self.is_polymorphic(&func.ty) && !self.builtins.contains(&func.name) {
                self.poly_fns.insert(func.name.clone(), func.clone());
            }
        }

        // Monomorphize instance methods too
        let instance_fns: Vec<TFunction> = module.instance_fns.iter()
            .map(|f| self.mono_function(f.clone()))
            .collect();

        // Walk all functions to collect specialization demands
        let functions: Vec<TFunction> = module.functions.iter()
            .map(|f| self.mono_function(f.clone()))
            .collect();

        // Keep all original functions (including polymorphic ones — they serve
        // as fallbacks for calls inside other polymorphic contexts where types
        // aren't resolved). Append generated specializations after.
        let mut result_fns: Vec<TFunction> = functions;
        result_fns.extend(self.generated.drain(..));

        TModule {
            data_defs: module.data_defs,
            functions: result_fns,
            instance_fns,
            has_main: module.has_main,
            exports: module.exports,
            record_accessors: module.record_accessors,
            newtypes: module.newtypes,
        }
    }

    /// Check if a parameterized instance exists (e.g., Show [a] for Show [Integer])
    /// Find a parameterized instance for a method on a concrete type.
    /// E.g., find show_PureMap for show on PureMap String Integer.
    fn resolve_parameterized_instance(&self, method: &str, concrete_ty: &Ty) -> Option<String> {
        let base = match concrete_ty {
            Ty::List(_) => "[]",
            Ty::App(f, _) => {
                let mut head = f.as_ref();
                loop {
                    match head {
                        Ty::Con(name) => break name.as_str(),
                        Ty::App(inner, _) => head = inner.as_ref(),
                        _ => return None,
                    }
                }
            }
            _ => return None,
        };
        // Look for exact base or parameterized key (e.g. "PureMap k v")
        if let Some(mangled) = self.instance_methods.get(&(method.to_string(), base.to_string())) {
            return Some(mangled.clone());
        }
        for ((m, t), mangled) in &self.instance_methods {
            if m == method && t.starts_with(&format!("{} ", base)) {
                return Some(mangled.clone());
            }
        }
        None
    }

    fn is_polymorphic(&self, ty: &Ty) -> bool {
        !ty.free_vars().is_empty()
    }

    /// Extract the type of the first argument from a function type
    fn first_arg_type(&self, ty: &Ty) -> Option<Ty> {
        match ty {
            Ty::Arrow(a, _) => Some(*a.clone()),
            _ => None,
        }
    }

    fn mangle_name(&mut self, name: &str, ty: &Ty) -> String {
        let ty_str = self.ty_to_suffix(ty);
        format!("{}_{}", name, ty_str)
    }

    fn ty_to_suffix(&self, ty: &Ty) -> String {
        match ty {
            Ty::Con(name) => name.clone(),
            Ty::Var(v) => format!("v{}", v.name),
            Ty::Arrow(a, b) => format!("{}T{}", self.ty_to_suffix(a), self.ty_to_suffix(b)),
            Ty::App(a, b) => format!("{}A{}", self.ty_to_suffix(a), self.ty_to_suffix(b)),
            Ty::List(a) => format!("L{}", self.ty_to_suffix(a)),
            Ty::IO(a) => format!("IO{}", self.ty_to_suffix(a)),
            Ty::LuaIO(s, a) => format!("LIO{}_{}", s.name, self.ty_to_suffix(a)),
            Ty::Forall(_, inner) => self.ty_to_suffix(inner),
            Ty::Unit => "Unit".to_string(),
        }
    }

    fn mono_function(&mut self, mut func: TFunction) -> TFunction {
        func.clauses = func.clauses.into_iter()
            .map(|c| self.mono_clause(c))
            .collect();
        func
    }

    fn mono_clause(&mut self, mut clause: TClause) -> TClause {
        clause.body = self.mono_expr(clause.body);
        clause.guards = clause.guards.into_iter().map(|g| TGuard {
            condition: self.mono_expr(g.condition),
            body: self.mono_expr(g.body),
        }).collect();
        clause.where_binds = clause.where_binds.into_iter().map(|ld| TLocalDef {
            name: ld.name,
            patterns: ld.patterns,
            body: self.mono_expr(ld.body),
        }).collect();
        clause
    }

    fn mono_expr(&mut self, expr: TExpr) -> TExpr {
        let ty = expr.ty.clone();
        let kind = match expr.kind {
            TExprKind::Var(ref name) => {
                // 1. Check for typeclass method resolution
                if self.class_methods.contains(name) && !self.is_polymorphic(&ty) {
                    // Extract the first argument type from the function type
                    if let Some(arg_ty) = self.first_arg_type(&ty) {
                        let ty_str = format!("{}", arg_ty);
                        let key = (name.clone(), ty_str.clone());
                        if let Some(mangled) = self.instance_methods.get(&key).cloned() {
                            return TExpr { kind: TExprKind::Var(mangled), ty };
                        } else if let Some(mangled) = self.resolve_parameterized_instance(name, &arg_ty) {
                            return TExpr { kind: TExprKind::Var(mangled), ty };
                        } else {
                            self.errors.push(format!(
                                "No instance for '{}' on type '{}'", name, ty_str
                            ));
                        }
                    }
                }
                // 2. Check for polymorphic function specialization
                // Handle calls inside specializations: if the type is still
                // polymorphic but we have specialization(s) for this function
                // name, use the most recent one (the recursive/sibling call
                // shares the same concrete type as the enclosing specialization)
                if self.poly_fns.contains_key(name) && self.is_polymorphic(&ty) {
                    let specs: Vec<_> = self.specializations.iter()
                        .filter(|(k, _)| k.name == *name)
                        .map(|(_, v)| v.clone())
                        .collect();
                    if !specs.is_empty() {
                        return TExpr { kind: TExprKind::Var(specs.last().unwrap().clone()), ty };
                    }
                }
                if self.poly_fns.contains_key(name) && !self.is_polymorphic(&ty) {
                    let key = SpecKey { name: name.clone(), ty: format!("{}", ty) };
                    let mangled = if let Some(existing) = self.specializations.get(&key) {
                        existing.clone()
                    } else {
                        // Check for polymorphic recursion (too many specializations)
                        let spec_count = self.specializations.keys()
                            .filter(|k| k.name == *name)
                            .count();
                        if spec_count > 16 {
                            self.errors.push(format!(
                                "Polymorphic recursion detected in '{}': \
                                 too many type specializations (the function likely calls \
                                 itself at a different type in each recursive step)",
                                name
                            ));
                            return TExpr { kind: expr.kind, ty };
                        }
                        let mangled = self.mangle_name(name, &ty);
                        self.specializations.insert(key, mangled.clone());
                        if let Some(poly_fn) = self.poly_fns.get(name).cloned() {
                            let mut spec_fn = poly_fn.clone();
                            spec_fn.name = mangled.clone();
                            spec_fn.ty = ty.clone();
                            spec_fn.specialized = true;
                            spec_fn = self.mono_function(spec_fn);
                            self.generated.push(spec_fn);
                        }
                        mangled
                    };
                    TExprKind::Var(mangled)
                } else {
                    expr.kind
                }
            }
            TExprKind::App(func, arg) => {
                // Check for class method application: describe arg
                // where describe is a class method and arg has a concrete type
                if let TExprKind::Var(ref fname) = func.kind {
                    if self.class_methods.contains(fname) {
                        let arg_ty = &arg.ty;
                        if !self.is_polymorphic(arg_ty) {
                            let ty_str = format!("{}", arg_ty);
                            let key = (fname.clone(), ty_str);
                            let resolved = self.instance_methods.get(&key).cloned()
                                .or_else(|| self.resolve_parameterized_instance(fname, arg_ty));
                            if let Some(mangled) = resolved {
                                let mono_arg = self.mono_expr(*arg);
                                return TExpr {
                                    kind: TExprKind::App(
                                        Box::new(TExpr::new(TExprKind::Var(mangled), func.ty.clone())),
                                        Box::new(mono_arg),
                                    ),
                                    ty,
                                };
                            }
                        }
                    }
                }
                TExprKind::App(
                    Box::new(self.mono_expr(*func)),
                    Box::new(self.mono_expr(*arg)),
                )
            }
            TExprKind::InfixApp { op, lhs, rhs } => {
                // Check for typeclass method resolution on infix operators
                if self.class_methods.contains(&op) && !self.is_polymorphic(&lhs.ty) {
                    let ty_str = format!("{}", lhs.ty);
                    let key = (op.clone(), ty_str.clone());
                    if let Some(mangled) = self.instance_methods.get(&key).cloned() {
                        let mono_lhs = self.mono_expr(*lhs);
                        let mono_rhs = self.mono_expr(*rhs);
                        return TExpr {
                            kind: TExprKind::App(
                                Box::new(TExpr::new(
                                    TExprKind::App(
                                        Box::new(TExpr::new(TExprKind::Var(mangled), Ty::Unit)),
                                        Box::new(mono_lhs),
                                    ),
                                    Ty::Unit,
                                )),
                                Box::new(mono_rhs),
                            ),
                            ty,
                        };
                    } else if self.resolve_parameterized_instance(&op, &lhs.ty).is_none() {
                        self.errors.push(format!(
                            "No instance for '{}' on type '{}'", op, ty_str
                        ));
                    }
                }
                TExprKind::InfixApp {
                    op,
                    lhs: Box::new(self.mono_expr(*lhs)),
                    rhs: Box::new(self.mono_expr(*rhs)),
                }
            }
            TExprKind::Negate(inner) => TExprKind::Negate(Box::new(self.mono_expr(*inner))),
            TExprKind::Lambda { params, body } => {
                TExprKind::Lambda { params, body: Box::new(self.mono_expr(*body)) }
            }
            TExprKind::If { cond, then_branch, else_branch } => {
                TExprKind::If {
                    cond: Box::new(self.mono_expr(*cond)),
                    then_branch: Box::new(self.mono_expr(*then_branch)),
                    else_branch: Box::new(self.mono_expr(*else_branch)),
                }
            }
            TExprKind::Case { scrutinee, branches } => {
                TExprKind::Case {
                    scrutinee: Box::new(self.mono_expr(*scrutinee)),
                    branches: branches.into_iter().map(|b| TCaseBranch {
                        pattern: b.pattern,
                        guards: b.guards,
                        body: self.mono_expr(b.body),
                    }).collect(),
                }
            }
            TExprKind::Let { binds, body } => {
                TExprKind::Let {
                    binds: binds.into_iter().map(|b| TLocalDef {
                        name: b.name, patterns: b.patterns,
                        body: self.mono_expr(b.body),
                    }).collect(),
                    body: Box::new(self.mono_expr(*body)),
                }
            }
            TExprKind::Do(stmts) => {
                TExprKind::Do(stmts.into_iter().map(|s| match s {
                    TDoStmt::Bind { name, ty, expr } => TDoStmt::Bind { name, ty, expr: self.mono_expr(expr) },
                    TDoStmt::DoLet { name, ty, expr } => TDoStmt::DoLet { name, ty, expr: self.mono_expr(expr) },
                    TDoStmt::Expr(e) => TDoStmt::Expr(self.mono_expr(e)),
                }).collect())
            }
            TExprKind::Paren(inner) => TExprKind::Paren(Box::new(self.mono_expr(*inner))),
            other => other,
        };
        TExpr { kind, ty }
    }
}
