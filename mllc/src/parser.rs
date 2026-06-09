use crate::ast::*;
use crate::lexer::{Located, Token};

pub struct Parser {
    tokens: Vec<Located>,
    pos: usize,
    /// Stack of indentation levels for layout tracking
    indent_stack: Vec<usize>,
    /// Current line's indentation
    current_indent: usize,
    /// Minimum indentation for current expression context
    expr_min_indent: usize,
}

impl Parser {
    fn new(tokens: Vec<Located>) -> Self {
        Parser {
            tokens,
            pos: 0,
            indent_stack: vec![0],
            current_indent: 0,
            expr_min_indent: 0,
        }
    }

    fn peek(&self) -> &Token {
        &self.tokens[self.pos].token
    }

    fn peek_loc(&self) -> &Located {
        &self.tokens[self.pos]
    }

    fn advance(&mut self) -> &Token {
        let tok = &self.tokens[self.pos].token;
        self.pos += 1;
        tok
    }

    fn expect(&mut self, expected: &Token) -> Result<(), String> {
        if self.peek() == expected {
            self.advance();
            Ok(())
        } else {
            let loc = self.peek_loc();
            Err(format!(
                "Expected {:?}, found {:?} at {}:{}",
                expected, loc.token, loc.line, loc.col
            ))
        }
    }

    fn at(&self, tok: &Token) -> bool {
        self.peek() == tok
    }

    fn at_eof(&self) -> bool {
        matches!(self.peek(), Token::EOF)
    }

    fn skip_indent(&mut self) {
        while let Token::Indent(n) = self.peek() {
            self.current_indent = *n;
            self.advance();
        }
    }

    fn skip_newlines_and_indent(&mut self) {
        loop {
            match self.peek() {
                Token::Indent(n) => {
                    self.current_indent = *n;
                    self.advance();
                }
                Token::Newline => {
                    self.advance();
                }
                _ => break,
            }
        }
    }

    /// Check if the current token is at or beyond a given indentation level
    fn at_indent_ge(&self, level: usize) -> bool {
        self.current_indent >= level
    }

    fn parse_module(&mut self) -> Result<Module, String> {
        let mut decls = Vec::new();
        self.skip_indent();

        while !self.at_eof() {
            let decl = self.parse_decl()?;
            decls.extend(decl);
            self.skip_newlines_and_indent();
        }

        // Merge consecutive FunDef declarations with the same name
        let mut merged: Vec<Decl> = Vec::new();
        for decl in decls {
            if let Decl::FunDef { name, clauses } = &decl {
                if let Some(Decl::FunDef { name: prev_name, clauses: prev_clauses }) = merged.last_mut() {
                    if prev_name == name {
                        prev_clauses.extend(clauses.clone());
                        continue;
                    }
                }
            }
            merged.push(decl);
        }

        Ok(Module { decls: merged })
    }

    fn parse_decl(&mut self) -> Result<Vec<Decl>, String> {
        self.skip_newlines_and_indent();

        match self.peek().clone() {
            Token::Data => self.parse_data_decl().map(|d| vec![d]),
            Token::Newtype => self.parse_newtype_decl().map(|d| vec![d]),
            Token::Import => self.parse_import_decl().map(|d| vec![d]),
            Token::Class => self.parse_class_decl(),
            Token::Instance => self.parse_instance_decl(),
            Token::KwType => self.parse_type_family_decl(),
            Token::Intrinsic => self.parse_intrinsic_decl(),
            Token::Export => self.parse_export_decl(),
            Token::Ident(_) => self.parse_value_decl(),
            Token::LeftParen => self.parse_operator_decl(),
            _ => {
                let loc = self.peek_loc();
                Err(format!(
                    "Unexpected token {:?} at top level at {}:{}",
                    loc.token, loc.line, loc.col
                ))
            }
        }
    }

    fn parse_data_decl(&mut self) -> Result<Decl, String> {
        self.expect(&Token::Data)?;
        let name = self.expect_upper_ident()?;

        let mut type_vars = Vec::new();
        while let Token::Ident(v) = self.peek() {
            type_vars.push(v.clone());
            self.advance();
        }

        // Check for GADT syntax
        if self.at(&Token::Where) {
            self.advance();
            // GADT constructors - for now just skip them and create a basic structure
            let mut constructors = Vec::new();
            self.skip_newlines_and_indent();
            let gadt_indent = self.current_indent;

            while !self.at_eof() && self.current_indent >= gadt_indent {
                if let Token::UpperIdent(_) = self.peek() {
                    let con_name = self.expect_upper_ident()?;
                    self.expect(&Token::DblColon)?;
                    let _ty = self.parse_type()?;
                    // For now, store as empty positional constructor
                    constructors.push(Constructor {
                        name: con_name,
                        fields: ConstructorFields::Positional(vec![]),
                    });
                    self.skip_newlines_and_indent();
                } else {
                    break;
                }
            }

            let deriving = self.parse_deriving()?;
            return Ok(Decl::DataDef {
                name,
                type_vars,
                constructors,
                deriving,
            });
        }

        self.expect(&Token::Eq)?;

        let mut constructors = Vec::new();
        constructors.push(self.parse_constructor()?);
        while self.at(&Token::Pipe) {
            self.advance();
            constructors.push(self.parse_constructor()?);
        }

        let deriving = self.parse_deriving()?;

        Ok(Decl::DataDef {
            name,
            type_vars,
            constructors,
            deriving,
        })
    }

    fn parse_constructor(&mut self) -> Result<Constructor, String> {
        let name = self.expect_upper_ident()?;

        // Check for record syntax
        if self.at(&Token::LeftBrace) {
            self.advance();
            let mut fields = Vec::new();
            loop {
                self.skip_newlines_and_indent();
                if self.at(&Token::RightBrace) {
                    break;
                }
                let field_name = self.expect_ident()?;
                self.expect(&Token::DblColon)?;
                let field_type = self.parse_type()?;
                fields.push((field_name, field_type));
                self.skip_newlines_and_indent();
                if self.at(&Token::Comma) {
                    self.advance();
                } else {
                    break;
                }
            }
            self.skip_newlines_and_indent();
            self.expect(&Token::RightBrace)?;
            return Ok(Constructor {
                name,
                fields: ConstructorFields::Named(fields),
            });
        }

        // Positional fields
        let mut fields = Vec::new();
        while self.is_type_atom_start() {
            fields.push(self.parse_type_atom()?);
        }

        Ok(Constructor {
            name,
            fields: ConstructorFields::Positional(fields),
        })
    }

    /// Parse optional `deriving (Show, Eq)` clause after a data declaration.
    fn parse_deriving(&mut self) -> Result<Vec<String>, String> {
        // Look ahead past newlines/indents for 'deriving'
        let save = self.pos;
        let save_indent = self.current_indent;
        self.skip_newlines_and_indent();
        if !self.at(&Token::Deriving) {
            self.pos = save;
            self.current_indent = save_indent;
            return Ok(vec![]);
        }
        self.advance(); // consume 'deriving'

        let mut classes = Vec::new();
        if self.at(&Token::LeftParen) {
            self.advance();
            loop {
                self.skip_newlines_and_indent();
                if self.at(&Token::RightParen) {
                    self.advance();
                    break;
                }
                classes.push(self.expect_upper_ident()?);
                self.skip_newlines_and_indent();
                if self.at(&Token::Comma) {
                    self.advance();
                } else {
                    self.expect(&Token::RightParen)?;
                    break;
                }
            }
        } else {
            // deriving Show (single class, no parens)
            classes.push(self.expect_upper_ident()?);
        }

        Ok(classes)
    }

    fn parse_newtype_decl(&mut self) -> Result<Decl, String> {
        self.expect(&Token::Newtype)?;
        let name = self.expect_upper_ident()?;

        let mut type_vars = Vec::new();
        while let Token::Ident(v) = self.peek() {
            type_vars.push(v.clone());
            self.advance();
        }

        self.expect(&Token::Eq)?;
        let inner = self.parse_type()?;

        Ok(Decl::NewtypeDef {
            name,
            type_vars,
            inner,
        })
    }

    fn parse_import_decl(&mut self) -> Result<Decl, String> {
        self.expect(&Token::Import)?;

        let qualified = if self.at(&Token::Qualified) {
            self.advance();
            true
        } else {
            false
        };

        let mut module_path = Vec::new();
        module_path.push(self.expect_upper_ident()?);
        while self.at(&Token::Operator(".".to_string())) {
            self.advance();
            module_path.push(self.expect_upper_ident()?);
        }

        if qualified {
            self.expect(&Token::As)?;
            let alias = self.expect_upper_ident()?;
            return Ok(Decl::Import {
                module_path,
                items: ImportItems::Qualified(alias),
            });
        }

        if self.at(&Token::LeftParen) {
            self.advance();
            let mut items = Vec::new();
            loop {
                if self.at(&Token::RightParen) {
                    break;
                }
                if let Token::UpperIdent(name) = self.peek().clone() {
                    self.advance();
                    if self.at(&Token::LeftParen) {
                        self.advance();
                        self.expect(&Token::Operator("..".to_string()))?;
                        self.expect(&Token::RightParen)?;
                        items.push(ImportItem::TypeAll(name));
                    } else {
                        items.push(ImportItem::TypeOnly(name));
                    }
                } else {
                    let name = self.expect_ident()?;
                    items.push(ImportItem::Value(name));
                }
                if self.at(&Token::Comma) {
                    self.advance();
                } else {
                    break;
                }
            }
            self.expect(&Token::RightParen)?;
            return Ok(Decl::Import {
                module_path,
                items: ImportItems::Specific(items),
            });
        }

        Ok(Decl::Import {
            module_path,
            items: ImportItems::All,
        })
    }

    fn parse_class_decl(&mut self) -> Result<Vec<Decl>, String> {
        self.expect(&Token::Class)?;

        // Parse optional superclass constraints: Eq a => or (Eq a, Show a) =>
        let save = self.pos;
        let save_indent = self.current_indent;
        let mut superclasses = Vec::new();

        // Try to parse constraints followed by =>
        let first = self.expect_upper_ident()?;
        if let Token::Ident(_) = self.peek() {
            let _tv = self.expect_ident()?;
            if self.at(&Token::FatArrow) {
                // Single constraint: Eq a =>
                superclasses.push(first);
                self.advance(); // consume =>
            } else {
                // No constraint, backtrack
                self.pos = save;
                self.current_indent = save_indent;
            }
        } else if self.at(&Token::Comma) {
            // Multiple constraints would need parens, skip for now
            self.pos = save;
            self.current_indent = save_indent;
        } else {
            self.pos = save;
            self.current_indent = save_indent;
        }

        let class_name = self.expect_upper_ident()?;
        let type_var = self.expect_ident()?;
        self.expect(&Token::Where)?;
        self.skip_newlines_and_indent();

        let mut methods = Vec::new();
        let method_indent = self.current_indent;

        loop {
            self.skip_newlines_and_indent();
            if self.at_eof() || self.current_indent < method_indent {
                break;
            }

            // Parse method signature: name :: type
            // Could be an operator like (+) :: ...
            let name = if self.at(&Token::LeftParen) {
                self.advance();
                let op = match self.peek().clone() {
                    Token::Operator(op) => { self.advance(); op }
                    _ => return Err("Expected operator in class method".into()),
                };
                self.expect(&Token::RightParen)?;
                op
            } else if let Token::Ident(name) = self.peek().clone() {
                self.advance();
                name
            } else {
                break;
            };

            self.expect(&Token::DblColon)?;
            let ty = self.parse_type()?;
            methods.push(ClassMethod { name, ty });
        }

        Ok(vec![Decl::ClassDecl { name: class_name, type_var, superclasses, methods }])
    }

    fn parse_instance_decl(&mut self) -> Result<Vec<Decl>, String> {
        self.expect(&Token::Instance)?;

        // Parse optional constraints: Eq a => or (Eq a, Show a) =>
        // Then: ClassName TargetType where
        // Strategy: save position, try to find =>, backtrack if not found
        let save = self.pos;
        let save_indent = self.current_indent;
        let class_name;
        let target_type;

        // Speculatively try: constraint(s) => class type where
        let first_name = self.expect_upper_ident()?;

        // Check for constraint: UpperIdent lowerIdent =>
        if let Token::Ident(_) = self.peek() {
            let save2 = self.pos;
            self.advance(); // consume the type var
            if self.at(&Token::FatArrow) {
                // Constraint found, skip it (constraint already validated by superclass)
                self.advance(); // consume =>
                class_name = self.expect_upper_ident()?;
                target_type = self.parse_type_atom()?;
            } else {
                // No =>, backtrack to after first_name
                self.pos = save2;
                // first_name is the class, next is the target type
                class_name = first_name;
                target_type = self.parse_type_atom()?;
            }
        } else {
            // target_type starts with uppercase — first_name is class, next is target
            class_name = first_name;
            target_type = self.parse_type_atom()?;
        }

        self.expect(&Token::Where)?;
        self.skip_newlines_and_indent();

        let mut methods = Vec::new();
        let method_indent = self.current_indent;

        loop {
            self.skip_newlines_and_indent();
            if self.at_eof() || self.current_indent < method_indent {
                break;
            }

            let name = if self.at(&Token::LeftParen) {
                self.advance();
                let op = match self.peek().clone() {
                    Token::Operator(op) => { self.advance(); op }
                    _ => return Err("Expected operator in instance method".into()),
                };
                self.expect(&Token::RightParen)?;
                op
            } else if let Token::Ident(name) = self.peek().clone() {
                self.advance();
                name
            } else {
                break;
            };

            // Collect all clauses for this method
            let clause = self.parse_clause()?;

            // Check if there's an existing method we should add a clause to
            if let Some(existing) = methods.iter_mut().find(|m: &&mut InstanceMethod| m.name == name) {
                existing.clauses.push(clause);
            } else {
                methods.push(InstanceMethod { name, clauses: vec![clause] });
            }
        }

        Ok(vec![Decl::InstanceDecl { class_name, target_type, methods }])
    }

    fn parse_export_decl(&mut self) -> Result<Vec<Decl>, String> {
        self.expect(&Token::Export)?;
        let name = self.expect_ident()?;
        self.expect(&Token::DblColon)?;
        let ty = self.parse_type()?;
        // ExportSig also serves as a TypeSig so the function gets type-checked
        Ok(vec![
            Decl::ExportSig { name: name.clone(), ty: ty.clone() },
            Decl::TypeSig { name, ty },
        ])
    }

    /// Parse: type family Name args where
    ///            Name Pattern = Result
    ///            ...
    fn parse_type_family_decl(&mut self) -> Result<Vec<Decl>, String> {
        self.expect(&Token::KwType)?;
        self.expect(&Token::Family)?;
        let name = self.expect_upper_ident()?;

        // Skip type parameter names (they're just documentation here)
        while matches!(self.peek(), Token::Ident(_)) {
            self.advance();
        }

        self.expect(&Token::Where)?;
        self.skip_newlines_and_indent();

        let mut equations = Vec::new();
        let eq_indent = self.current_indent;

        loop {
            self.skip_newlines_and_indent();
            if self.at_eof() || self.current_indent < eq_indent {
                break;
            }
            // Each equation: FamilyName argType... = resultType
            if let Token::UpperIdent(ref eq_name) = self.peek().clone() {
                if *eq_name != name {
                    break;
                }
                self.advance(); // consume family name
                let mut args = Vec::new();
                while !self.at(&Token::Eq) && !self.at_eof() {
                    args.push(self.parse_type_atom()?);
                }
                self.expect(&Token::Eq)?;
                let result = self.parse_type()?;
                equations.push(TypeFamilyEq { args, result });
            } else {
                break;
            }
        }

        Ok(vec![Decl::TypeFamily { name, equations }])
    }

    fn parse_intrinsic_decl(&mut self) -> Result<Vec<Decl>, String> {
        self.expect(&Token::Intrinsic)?;
        // Skip intrinsic declarations for now
        while !self.at_eof() {
            match self.peek() {
                Token::Indent(n) if *n == 0 => break,
                Token::EOF => break,
                _ => { self.advance(); }
            }
        }
        Ok(vec![])
    }

    /// Parse a value declaration (type signature or function definition).
    fn parse_value_decl(&mut self) -> Result<Vec<Decl>, String> {
        let name = self.expect_ident()?;

        // Type signature: `name :: type`
        if self.at(&Token::DblColon) {
            self.advance();
            let ty = self.parse_type()?;
            return Ok(vec![Decl::TypeSig { name, ty }]);
        }

        // Function definition: `name patterns = expr`
        let clause = self.parse_clause()?;

        Ok(vec![Decl::FunDef {
            name,
            clauses: vec![clause],
        }])
    }

    /// Parse an operator definition like `(+) a b = ...`
    fn parse_operator_decl(&mut self) -> Result<Vec<Decl>, String> {
        self.expect(&Token::LeftParen)?;
        let op = match self.peek().clone() {
            Token::Operator(op) => {
                self.advance();
                op
            }
            _ => {
                let loc = self.peek_loc();
                return Err(format!("Expected operator at {}:{}", loc.line, loc.col));
            }
        };
        self.expect(&Token::RightParen)?;

        // Type signature: `(op) :: type`
        if self.at(&Token::DblColon) {
            self.advance();
            let ty = self.parse_type()?;
            return Ok(vec![Decl::TypeSig { name: op, ty }]);
        }

        let clause = self.parse_clause()?;
        Ok(vec![Decl::FunDef {
            name: op,
            clauses: vec![clause],
        }])
    }

    fn parse_clause(&mut self) -> Result<Clause, String> {
        let loc = self.peek_loc();
        let span = Span::new(loc.line, loc.col);

        let mut patterns = Vec::new();
        while self.is_pattern_atom_start() || matches!(self.peek(), Token::UpperIdent(_)) {
            if let Token::UpperIdent(_) = self.peek() {
                // Constructor or True/False at clause level — parse as full pattern
                // but don't consume args (they're separate clause patterns)
                let pat = match self.peek().clone() {
                    Token::UpperIdent(name) => {
                        self.advance();
                        match name.as_str() {
                            "True" => Pattern::LitPat(Literal::Bool(true)),
                            "False" => Pattern::LitPat(Literal::Bool(false)),
                            _ => Pattern::Constructor { name, args: vec![] },
                        }
                    }
                    _ => unreachable!(),
                };
                patterns.push(pat);
            } else {
                patterns.push(self.parse_pattern_atom()?);
            }
        }

        // Guards
        let mut guards = Vec::new();
        self.skip_newlines_and_indent();
        if self.at(&Token::Pipe) {
            while self.at(&Token::Pipe) {
                self.advance();
                let condition = self.parse_expr()?;
                self.expect(&Token::Eq)?;
                let body = self.parse_expr()?;
                guards.push(Guard { condition, body });
                self.skip_newlines_and_indent();
            }
            return Ok(Clause {
                patterns,
                guards,
                body: Expr::Var("undefined".to_string()),
                where_binds: vec![],
                span,
            });
        }

        self.expect(&Token::Eq)?;
        let body = self.parse_expr()?;

        // where clause
        let where_binds = self.parse_where()?;

        Ok(Clause {
            patterns,
            guards,
            body,
            where_binds,
            span,
        })
    }

    fn parse_where(&mut self) -> Result<Vec<LocalDef>, String> {
        self.skip_newlines_and_indent();
        if !self.at(&Token::Where) {
            return Ok(vec![]);
        }
        self.advance();
        self.skip_newlines_and_indent();

        let mut binds = Vec::new();
        let where_indent = self.current_indent;

        loop {
            self.skip_newlines_and_indent();
            if self.at_eof() || self.current_indent < where_indent {
                break;
            }
            if !matches!(self.peek(), Token::Ident(_)) {
                break;
            }
            let name = self.expect_ident()?;
            let mut patterns = Vec::new();
            while self.is_pattern_start() {
                patterns.push(self.parse_pattern_atom()?);
            }
            self.expect(&Token::Eq)?;
            let body = self.parse_expr()?;
            binds.push(LocalDef {
                name,
                patterns,
                body,
            });
        }

        Ok(binds)
    }

    // --- Type parsing ---

    fn parse_type(&mut self) -> Result<Type, String> {
        // Check for forall: `forall s. type`
        if let Token::Ident(ref name) = self.peek().clone() {
            if name == "forall" {
                self.advance();
                let var = self.expect_ident()?;
                self.expect(&Token::Operator(".".to_string()))?;
                let inner = self.parse_type()?;
                return Ok(Type::Forall {
                    var,
                    inner: Box::new(inner),
                });
            }
        }

        // Check for constraints: `Show a => ...`
        let save = self.pos;
        if let Ok(constraints) = self.try_parse_constraints() {
            if self.at(&Token::FatArrow) {
                self.advance();
                let ty = self.parse_type_arrow()?;
                return Ok(Type::Constrained {
                    constraints,
                    ty: Box::new(ty),
                });
            }
        }
        self.pos = save;
        self.parse_type_arrow()
    }

    fn try_parse_constraints(&mut self) -> Result<Vec<Constraint>, String> {
        let mut constraints = Vec::new();
        if self.at(&Token::LeftParen) {
            self.advance();
            loop {
                let class_name = self.expect_upper_ident()?;
                let type_arg = self.parse_type_atom()?;
                constraints.push(Constraint { class_name, type_arg });
                if self.at(&Token::Comma) {
                    self.advance();
                } else {
                    break;
                }
            }
            self.expect(&Token::RightParen)?;
        } else {
            let class_name = self.expect_upper_ident()?;
            let type_arg = self.parse_type_atom()?;
            constraints.push(Constraint { class_name, type_arg });
        }
        Ok(constraints)
    }

    fn parse_type_arrow(&mut self) -> Result<Type, String> {
        let lhs = self.parse_type_app()?;
        if self.at(&Token::Arrow) {
            self.advance();
            let rhs = self.parse_type_arrow()?;
            Ok(Type::Arrow(Box::new(lhs), Box::new(rhs)))
        } else {
            Ok(lhs)
        }
    }

    fn parse_type_app(&mut self) -> Result<Type, String> {
        let mut ty = self.parse_type_atom()?;
        while self.is_type_atom_start() {
            let arg = self.parse_type_atom()?;
            ty = Type::App(Box::new(ty), Box::new(arg));
        }
        Ok(ty)
    }

    fn is_type_atom_start(&self) -> bool {
        matches!(
            self.peek(),
            Token::UpperIdent(_)
                | Token::Ident(_)
                | Token::LeftParen
                | Token::LeftBracket
                | Token::StrLit(_)
        )
    }

    fn parse_type_atom(&mut self) -> Result<Type, String> {
        match self.peek().clone() {
            Token::UpperIdent(name) => {
                self.advance();
                match name.as_str() {
                    "IO" => {
                        if self.is_type_atom_start() {
                            let inner = self.parse_type_atom()?;
                            Ok(Type::IO(Box::new(inner)))
                        } else {
                            Ok(Type::Con(name))
                        }
                    }
                    "LuaIO" if !matches!(self.peek(), Token::StrLit(_)) => {
                        // LuaIO s a — scoped Lua IO monad (not the FFI type family)
                        let scope_var = self.expect_ident()?;
                        let inner = self.parse_type_atom()?;
                        Ok(Type::ScopedLuaIO {
                            scope_var,
                            inner: Box::new(inner),
                        })
                    }
                    "LuaPure" => {
                        // LuaPure "lua.func.name" ReturnType
                        let lua_name = match self.peek().clone() {
                            Token::StrLit(s) => { self.advance(); s }
                            _ => return Err("LuaPure expects a string literal".into()),
                        };
                        let result = self.parse_type_atom()?;
                        Ok(Type::LuaPure { lua_name, result: Box::new(result) })
                    }
                    "LuaIO" => {
                        // LuaIO "lua.func.name" ReturnType
                        let lua_name = match self.peek().clone() {
                            Token::StrLit(s) => { self.advance(); s }
                            _ => return Err("LuaIO expects a string literal".into()),
                        };
                        let result = self.parse_type_atom()?;
                        Ok(Type::LuaIO { lua_name, result: Box::new(result) })
                    }
                    _ => Ok(Type::Con(name)),
                }
            }
            Token::Ident(name) => {
                self.advance();
                Ok(Type::Var(name))
            }
            Token::LeftParen => {
                self.advance();
                if self.at(&Token::RightParen) {
                    self.advance();
                    return Ok(Type::Unit);
                }
                // Check for operator type like (+)
                if let Token::Operator(_) = self.peek() {
                    let _op = self.advance().clone();
                    self.expect(&Token::RightParen)?;
                    // skip for now
                    return Ok(Type::Unit);
                }
                let ty = self.parse_type()?;
                self.expect(&Token::RightParen)?;
                Ok(Type::Paren(Box::new(ty)))
            }
            Token::LeftBracket => {
                self.advance();
                let inner = self.parse_type()?;
                self.expect(&Token::RightBracket)?;
                Ok(Type::List(Box::new(inner)))
            }
            Token::StrLit(s) => {
                // Type-level string literal (Symbol kind)
                self.advance();
                Ok(Type::Con(format!("\"{}\"", s)))
            }
            _ => {
                let loc = self.peek_loc();
                Err(format!(
                    "Expected type, found {:?} at {}:{}",
                    loc.token, loc.line, loc.col
                ))
            }
        }
    }

    // --- Expression parsing ---

    fn parse_expr(&mut self) -> Result<Expr, String> {
        // Skip leading indent/newlines to find the actual expression start
        self.skip_newlines_and_indent();
        self.expr_min_indent = self.current_indent;
        let expr = self.parse_expr_infix(0)?;

        // Type ascription: expr :: Type (parsed and discarded,
        // the type checker uses its own inference)
        if self.at(&Token::DblColon) {
            self.advance();
            let _ty = self.parse_type()?;
            // TODO: use this type annotation for bidirectional checking
        }

        Ok(expr)
    }

    fn parse_expr_infix(&mut self, min_prec: u8) -> Result<Expr, String> {
        let mut lhs = self.parse_expr_prefix()?;

        loop {
            // Try to consume indentation for continuation lines
            // Only if the next real token after indent is an operator
            // and the indent is deeper than the expression start
            if let Token::Indent(n) = self.peek() {
                let n = *n;
                if n > self.expr_min_indent {
                    let save = self.pos;
                    self.advance(); // consume indent
                    self.current_indent = n;
                    // Check if next token is an operator (continuation)
                    if !matches!(self.peek(), Token::Operator(_) | Token::Backtick) {
                        // Not a continuation — put it back
                        self.pos = save;
                    }
                }
            }

            // Check for operator
            match self.peek().clone() {
                Token::Operator(ref op) => {
                    let (lp, rp) = operator_precedence(op);
                    if lp < min_prec {
                        break;
                    }
                    let op = op.clone();
                    self.advance();
                    self.skip_newlines_and_indent();
                    let rhs = self.parse_expr_infix(rp)?;
                    lhs = Expr::InfixApp {
                        op,
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    };
                }
                Token::Backtick => {
                    self.advance();
                    let func = self.expect_ident()?;
                    self.expect(&Token::Backtick)?;
                    self.skip_newlines_and_indent();
                    let rhs = self.parse_expr_infix(5)?;
                    lhs = Expr::InfixApp {
                        op: func,
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    };
                }
                _ => break,
            }
        }

        Ok(lhs)
    }

    fn parse_expr_prefix(&mut self) -> Result<Expr, String> {
        // Negation
        if let Token::Operator(ref op) = self.peek().clone() {
            if op == "-" {
                self.advance();
                let expr = self.parse_expr_app()?;
                return Ok(Expr::Negate(Box::new(expr)));
            }
        }
        self.parse_expr_app()
    }

    fn parse_expr_app(&mut self) -> Result<Expr, String> {
        let mut func = self.parse_expr_atom_dotted()?;

        while self.is_expr_atom_start_in_context() {
            let arg = self.parse_expr_atom_dotted()?;
            func = Expr::App(Box::new(func), Box::new(arg));
        }

        Ok(func)
    }

    /// Parse an atom optionally followed by one or more `.field` accesses.
    /// `expr.field` desugars to `(field expr)`.
    /// Only applies when `.` is adjacent to the preceding token (no space),
    /// to distinguish from function composition `f . g`.
    fn parse_expr_atom_dotted(&mut self) -> Result<Expr, String> {
        let mut expr = self.parse_expr_atom()?;

        while self.at(&Token::Operator(".".to_string())) {
            // Check adjacency: the '.' must be on the same line as the
            // previous token and immediately follow it (no whitespace).
            let prev_tok = &self.tokens[self.pos - 1];
            let dot_tok = &self.tokens[self.pos];
            if dot_tok.line != prev_tok.line {
                break;
            }
            // Estimate end column of previous token
            let prev_end = prev_tok.col + token_len(&prev_tok.token);
            if dot_tok.col != prev_end {
                break; // there's a gap — this is composition, not field access
            }
            if self.pos + 1 < self.tokens.len() {
                if let Token::Ident(_) = &self.tokens[self.pos + 1].token {
                    self.advance(); // consume '.'
                    if let Token::Ident(field) = self.peek().clone() {
                        self.advance(); // consume field name
                        expr = Expr::App(Box::new(Expr::Var(field)), Box::new(expr));
                        continue;
                    }
                }
            }
            break;
        }

        Ok(expr)
    }

    /// Check if the next token could start an expression atom,
    /// respecting indentation context. Stops when we've returned to
    /// a line at or below the expression's starting indentation.
    fn is_expr_atom_start_in_context(&self) -> bool {
        // If there's an Indent token next, check indentation
        if let Token::Indent(n) = self.peek() {
            if *n <= self.expr_min_indent {
                return false;
            }
        }
        if !self.is_expr_atom_start() {
            return false;
        }
        // If current_indent dropped to at or below expression start,
        // and the next token is at the start of a line (col 1),
        // don't consume it — it's a new declaration
        let loc = self.peek_loc();
        if self.current_indent <= self.expr_min_indent && loc.col == 1 {
            return false;
        }
        true
    }

    fn is_expr_atom_start(&self) -> bool {
        matches!(
            self.peek(),
            Token::Ident(_)
                | Token::UpperIdent(_)
                | Token::IntLit(_)
                | Token::NumLit(_)
                | Token::StrLit(_)
                | Token::LeftParen
                | Token::LeftBracket
        )
    }

    fn parse_expr_atom(&mut self) -> Result<Expr, String> {
        match self.peek().clone() {
            Token::IntLit(n) => {
                self.advance();
                Ok(Expr::Lit(Literal::Integer(n)))
            }
            Token::NumLit(n) => {
                self.advance();
                Ok(Expr::Lit(Literal::Number(n)))
            }
            Token::StrLit(s) => {
                self.advance();
                Ok(Expr::Lit(Literal::Str(s)))
            }
            Token::Ident(name) => {
                self.advance();
                Ok(Expr::Var(name))
            }
            Token::UpperIdent(name) => {
                self.advance();
                match name.as_str() {
                    "True" => Ok(Expr::Lit(Literal::Bool(true))),
                    "False" => Ok(Expr::Lit(Literal::Bool(false))),
                    _ => {
                        // Check for record construction: Con { field = val, ... }
                        if self.at(&Token::LeftBrace) {
                            self.advance();
                            let mut fields = Vec::new();
                            loop {
                                self.skip_newlines_and_indent();
                                if self.at(&Token::RightBrace) {
                                    self.advance();
                                    break;
                                }
                                let field_name = self.expect_ident()?;
                                self.expect(&Token::Eq)?;
                                let value = self.parse_expr()?;
                                fields.push((field_name, value));
                                self.skip_newlines_and_indent();
                                if self.at(&Token::Comma) {
                                    self.advance();
                                } else {
                                    self.skip_newlines_and_indent();
                                    self.expect(&Token::RightBrace)?;
                                    break;
                                }
                            }
                            Ok(Expr::RecordCon { constructor: name, fields })
                        } else {
                            Ok(Expr::Con(name))
                        }
                    }
                }
            }
            Token::LeftParen => {
                self.advance();

                // Check for operator-starting forms: (+), (+1), (-)
                if let Token::Operator(op) = self.peek().clone() {
                    self.advance(); // consume operator
                    if self.at(&Token::RightParen) {
                        // (op) — operator as function
                        self.advance();
                        return Ok(Expr::OpFunc(op));
                    }
                    if op == "-" {
                        // (-expr) is negation, not a section
                        let inner = self.parse_expr()?;
                        self.expect(&Token::RightParen)?;
                        return Ok(Expr::Paren(Box::new(Expr::Negate(Box::new(inner)))));
                    }
                    // (op expr) — right section: \x -> x op expr
                    let rhs = self.parse_expr()?;
                    self.expect(&Token::RightParen)?;
                    return Ok(Expr::Lambda {
                        params: vec!["_sec".into()],
                        body: Box::new(Expr::InfixApp {
                            op,
                            lhs: Box::new(Expr::Var("_sec".into())),
                            rhs: Box::new(rhs),
                        }),
                    });
                }

                // () — unit
                if self.at(&Token::RightParen) {
                    self.advance();
                    return Ok(Expr::Lit(Literal::Bool(true))); // unit value, placeholder
                }

                // Try to detect left section: (expr op)
                // Parse application-level (no infix) and check for op )
                let save_pos = self.pos;
                let save_indent = self.current_indent;
                let lhs = self.parse_expr_app()?;
                if let Token::Operator(op) = self.peek().clone() {
                    {
                        let after_op = self.pos + 1;
                        if after_op < self.tokens.len() {
                            if self.tokens[after_op].token == Token::RightParen {
                                // (expr op) — left section: \x -> expr op x
                                self.advance(); // consume operator
                                self.advance(); // consume )
                                return Ok(Expr::Lambda {
                                    params: vec!["_sec".into()],
                                    body: Box::new(Expr::InfixApp {
                                        op,
                                        lhs: Box::new(lhs),
                                        rhs: Box::new(Expr::Var("_sec".into())),
                                    }),
                                });
                            }
                        }
                    }
                }

                // Not a section — backtrack and parse full expression
                self.pos = save_pos;
                self.current_indent = save_indent;
                let expr = self.parse_expr()?;
                self.expect(&Token::RightParen)?;
                Ok(Expr::Paren(Box::new(expr)))
            }
            Token::LeftBracket => {
                self.advance();
                let mut items = Vec::new();
                if !self.at(&Token::RightBracket) {
                    items.push(self.parse_expr()?);
                    while self.at(&Token::Comma) {
                        self.advance();
                        items.push(self.parse_expr()?);
                    }
                }
                self.expect(&Token::RightBracket)?;
                // Build a list from constructors
                let mut list = Expr::Con("[]".to_string());
                for item in items.into_iter().rev() {
                    list = Expr::App(
                        Box::new(Expr::App(
                            Box::new(Expr::Con(":".to_string())),
                            Box::new(item),
                        )),
                        Box::new(list),
                    );
                }
                Ok(list)
            }
            Token::If => {
                self.advance();
                let cond = self.parse_expr()?;
                self.expect(&Token::Then)?;
                let then_branch = self.parse_expr()?;
                self.expect(&Token::Else)?;
                let else_branch = self.parse_expr()?;
                Ok(Expr::If {
                    cond: Box::new(cond),
                    then_branch: Box::new(then_branch),
                    else_branch: Box::new(else_branch),
                })
            }
            Token::Case => {
                self.advance();
                let scrutinee = self.parse_expr()?;
                self.expect(&Token::Of)?;
                self.skip_newlines_and_indent();
                let case_indent = self.current_indent;
                let mut branches = Vec::new();

                loop {
                    self.skip_newlines_and_indent();
                    if self.at_eof() || self.current_indent < case_indent {
                        break;
                    }
                    let pattern = self.parse_pattern()?;

                    if self.at(&Token::Pipe) {
                        // Guards on case branch
                        let mut guards = Vec::new();
                        while self.at(&Token::Pipe) {
                            self.advance();
                            let condition = self.parse_expr()?;
                            self.expect(&Token::Arrow)?;
                            let body = self.parse_expr()?;
                            guards.push(Guard { condition, body });
                            self.skip_newlines_and_indent();
                        }
                        branches.push(CaseBranch {
                            pattern,
                            guards,
                            body: Expr::Var("undefined".to_string()),
                        });
                    } else {
                        self.expect(&Token::Arrow)?;
                        let body = self.parse_expr()?;
                        branches.push(CaseBranch {
                            pattern,
                            guards: vec![],
                            body,
                        });
                    }
                }

                Ok(Expr::Case {
                    scrutinee: Box::new(scrutinee),
                    branches,
                })
            }
            Token::Let => {
                self.advance();
                self.skip_newlines_and_indent();
                let mut binds = Vec::new();
                let let_indent = self.current_indent;

                loop {
                    self.skip_newlines_and_indent();
                    if self.at_eof() || self.current_indent < let_indent {
                        break;
                    }
                    if self.at(&Token::In) {
                        break;
                    }
                    if !matches!(self.peek(), Token::Ident(_)) {
                        break;
                    }
                    let name = self.expect_ident()?;
                    let mut patterns = Vec::new();
                    while self.is_pattern_start() {
                        patterns.push(self.parse_pattern_atom()?);
                    }
                    self.expect(&Token::Eq)?;
                    let body = self.parse_expr()?;
                    binds.push(LocalDef { name, patterns, body });
                }

                self.expect(&Token::In)?;
                self.skip_newlines_and_indent();
                let body = self.parse_expr()?;

                Ok(Expr::Let {
                    binds,
                    body: Box::new(body),
                })
            }
            Token::Do => {
                self.advance();
                self.skip_newlines_and_indent();
                let do_indent = self.current_indent;
                let mut stmts = Vec::new();

                loop {
                    self.skip_newlines_and_indent();
                    if self.at_eof() || self.current_indent < do_indent {
                        break;
                    }

                    // Check for `let name = expr`
                    if self.at(&Token::Let) {
                        self.advance();
                        let name = self.expect_ident()?;
                        self.expect(&Token::Eq)?;
                        let expr = self.parse_expr()?;
                        stmts.push(DoStmt::DoLet { name, expr });
                        continue;
                    }

                    // Check for `name <- expr` (bind)
                    let save = self.pos;
                    if let Token::Ident(name) = self.peek().clone() {
                        self.advance();
                        if self.at(&Token::Bind) {
                            self.advance();
                            let expr = self.parse_expr()?;
                            stmts.push(DoStmt::Bind { name, expr });
                            continue;
                        }
                        self.pos = save;
                    }

                    // Bare expression
                    let expr = self.parse_expr()?;
                    stmts.push(DoStmt::Expr(expr));
                }

                Ok(Expr::Do(stmts))
            }
            Token::Backslash => {
                self.advance();
                let mut params = Vec::new();
                while let Token::Ident(name) = self.peek().clone() {
                    params.push(name);
                    self.advance();
                }
                if params.is_empty() {
                    // Could be \_ ->
                    if self.at(&Token::Underscore) {
                        self.advance();
                        params.push("_".to_string());
                    } else {
                        let loc = self.peek_loc();
                        return Err(format!(
                            "Expected lambda parameter at {}:{}",
                            loc.line, loc.col
                        ));
                    }
                }
                self.expect(&Token::Arrow)?;
                let body = self.parse_expr()?;
                Ok(Expr::Lambda {
                    params,
                    body: Box::new(body),
                })
            }
            _ => {
                let loc = self.peek_loc();
                Err(format!(
                    "Expected expression, found {:?} at {}:{}",
                    loc.token, loc.line, loc.col
                ))
            }
        }
    }

    // --- Pattern parsing ---

    fn parse_pattern(&mut self) -> Result<Pattern, String> {
        let lhs = if let Token::UpperIdent(name) = self.peek().clone() {
            self.advance();
            // True/False are literal patterns, not constructors
            match name.as_str() {
                "True" => Pattern::LitPat(Literal::Bool(true)),
                "False" => Pattern::LitPat(Literal::Bool(false)),
                _ => {
                    let mut args = Vec::new();
                    while self.is_pattern_atom_start() {
                        args.push(self.parse_pattern_atom()?);
                    }
                    if args.is_empty() {
                        Pattern::Constructor { name, args: vec![] }
                    } else {
                        Pattern::Constructor { name, args }
                    }
                }
            }
        } else {
            self.parse_pattern_atom()?
        };

        // Check for infix cons pattern: x : xs
        if let Token::Operator(ref op) = self.peek().clone() {
            if op == ":" {
                self.advance();
                let rhs = self.parse_pattern()?;
                return Ok(Pattern::Constructor {
                    name: ":".to_string(),
                    args: vec![lhs, rhs],
                });
            }
        }

        Ok(lhs)
    }

    fn is_pattern_start(&self) -> bool {
        self.is_pattern_atom_start() || matches!(self.peek(), Token::UpperIdent(_))
    }

    fn is_pattern_atom_start(&self) -> bool {
        matches!(
            self.peek(),
            Token::Ident(_)
                | Token::Underscore
                | Token::IntLit(_)
                | Token::NumLit(_)
                | Token::StrLit(_)
                | Token::LeftParen
                | Token::LeftBracket
        )
    }

    fn parse_pattern_atom(&mut self) -> Result<Pattern, String> {
        match self.peek().clone() {
            Token::Ident(name) => {
                self.advance();
                Ok(Pattern::Var(name))
            }
            Token::Underscore => {
                self.advance();
                Ok(Pattern::Wildcard)
            }
            Token::IntLit(n) => {
                self.advance();
                Ok(Pattern::LitPat(Literal::Integer(n)))
            }
            Token::NumLit(n) => {
                self.advance();
                Ok(Pattern::LitPat(Literal::Number(n)))
            }
            Token::StrLit(s) => {
                self.advance();
                Ok(Pattern::LitPat(Literal::Str(s)))
            }
            Token::LeftParen => {
                self.advance();
                if self.at(&Token::RightParen) {
                    self.advance();
                    return Ok(Pattern::Constructor {
                        name: "()".to_string(),
                        args: vec![],
                    });
                }
                let inner = self.parse_pattern()?;
                self.expect(&Token::RightParen)?;
                Ok(Pattern::Paren(Box::new(inner)))
            }
            Token::LeftBracket => {
                self.advance();
                if self.at(&Token::RightBracket) {
                    self.advance();
                    return Ok(Pattern::Constructor {
                        name: "[]".to_string(),
                        args: vec![],
                    });
                }
                // [x, y, z] pattern => x : y : z : []
                let mut items = Vec::new();
                items.push(self.parse_pattern()?);
                while self.at(&Token::Comma) {
                    self.advance();
                    items.push(self.parse_pattern()?);
                }
                self.expect(&Token::RightBracket)?;
                let mut pat = Pattern::Constructor { name: "[]".to_string(), args: vec![] };
                for item in items.into_iter().rev() {
                    pat = Pattern::Constructor { name: ":".to_string(), args: vec![item, pat] };
                }
                Ok(pat)
            }
            Token::UpperIdent(name) => {
                self.advance();
                Ok(Pattern::Constructor {
                    name,
                    args: vec![],
                })
            }
            _ => {
                let loc = self.peek_loc();
                Err(format!(
                    "Expected pattern, found {:?} at {}:{}",
                    loc.token, loc.line, loc.col
                ))
            }
        }
    }

    // --- Helpers ---

    fn expect_ident(&mut self) -> Result<String, String> {
        match self.peek().clone() {
            Token::Ident(name) => {
                self.advance();
                Ok(name)
            }
            _ => {
                let loc = self.peek_loc();
                Err(format!(
                    "Expected identifier, found {:?} at {}:{}",
                    loc.token, loc.line, loc.col
                ))
            }
        }
    }

    fn expect_upper_ident(&mut self) -> Result<String, String> {
        match self.peek().clone() {
            Token::UpperIdent(name) => {
                self.advance();
                Ok(name)
            }
            _ => {
                let loc = self.peek_loc();
                Err(format!(
                    "Expected type/constructor name, found {:?} at {}:{}",
                    loc.token, loc.line, loc.col
                ))
            }
        }
    }
}

/// Operator precedence (left binding power, right binding power).
/// Based on Haskell defaults.
fn operator_precedence(op: &str) -> (u8, u8) {
    match op {
        "$" => (1, 0),  // right-associative, lowest precedence
        "||" => (2, 3),
        "&&" => (3, 4),
        "==" | "/=" | "<" | ">" | "<=" | ">=" => (4, 5),
        ":" => (5, 4),  // right-associative cons
        "++" => (5, 6),
        "+" | "-" => (6, 7),
        "*" | "/" => (7, 8),
        "^" => (9, 8), // right-associative
        "." => (9, 10),
        _ => (9, 10), // default high precedence
    }
}

/// Estimate the source length of a token for adjacency checks.
fn token_len(tok: &Token) -> usize {
    match tok {
        Token::Ident(s) | Token::UpperIdent(s) | Token::StrLit(s) => s.len(),
        Token::Operator(s) => s.len(),
        Token::IntLit(n) => format!("{}", n).len(),
        Token::NumLit(n) => format!("{}", n).len(),
        Token::LeftParen | Token::RightParen | Token::LeftBracket
        | Token::RightBracket | Token::LeftBrace | Token::RightBrace
        | Token::Comma | Token::Semicolon | Token::Backtick
        | Token::Backslash | Token::Underscore | Token::At => 1,
        Token::Arrow | Token::FatArrow | Token::DblColon | Token::Eq
        | Token::Pipe | Token::Bind => 2,
        _ => 1,
    }
}

pub fn parse(tokens: &[Located]) -> Result<Module, String> {
    let mut parser = Parser::new(tokens.to_vec());
    parser.parse_module()
}
