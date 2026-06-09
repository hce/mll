/// Module resolution and loading
///
/// Each .mll file is a module. Module names map to file paths:
///   import Data.Tree  =>  Data/Tree.mll
///
/// When compiling a module, imported .mll files are parsed, type-checked,
/// and their declarations are merged into the current module's environment.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::fs;

use crate::ast::*;
use crate::lexer;
use crate::parser;

/// Resolved module with its declarations
#[derive(Debug)]
pub struct ResolvedModule {
    pub path: PathBuf,
    pub module: Module,
}

/// Module loader
pub struct ModuleLoader {
    /// Search paths for modules
    search_paths: Vec<PathBuf>,
    /// Already loaded modules (path -> declarations)
    loaded: HashMap<String, Module>,
}

impl ModuleLoader {
    pub fn new(source_dir: &Path) -> Self {
        ModuleLoader {
            search_paths: vec![source_dir.to_path_buf()],
            loaded: HashMap::new(),
        }
    }

    pub fn add_search_path(&mut self, path: PathBuf) {
        self.search_paths.push(path);
    }

    /// Resolve a module path (e.g., ["Data", "Tree"]) to a file path
    fn resolve_path(&self, module_path: &[String]) -> Option<PathBuf> {
        let relative: PathBuf = module_path.iter().collect();
        let filename = format!("{}.mll", relative.display());

        for search_dir in &self.search_paths {
            let full_path = search_dir.join(&filename);
            if full_path.exists() {
                return Some(full_path);
            }
        }
        None
    }

    /// Load and parse a module, caching the result
    pub fn load_module(&mut self, module_path: &[String]) -> Result<&Module, String> {
        let key = module_path.join(".");

        if self.loaded.contains_key(&key) {
            return Ok(self.loaded.get(&key).unwrap());
        }

        let file_path = self.resolve_path(module_path)
            .ok_or_else(|| format!("Cannot find module '{}'", key))?;

        let source = fs::read_to_string(&file_path)
            .map_err(|e| format!("Error reading {}: {}", file_path.display(), e))?;

        let tokens = lexer::lex(&source)?;
        let module = parser::parse(&tokens)?;

        self.loaded.insert(key.clone(), module);
        Ok(self.loaded.get(&key).unwrap())
    }

    /// Process all imports in a module, returning merged declarations.
    /// The imported declarations are prepended to the module's own declarations.
    pub fn resolve_imports(&mut self, module: &Module) -> Result<Module, String> {
        let mut imported_decls: Vec<Decl> = Vec::new();
        let mut own_decls: Vec<Decl> = Vec::new();
        let mut seen_imports: HashSet<String> = HashSet::new();

        for decl in &module.decls {
            match decl {
                Decl::Import { module_path, items } => {
                    let key = module_path.join(".");
                    if seen_imports.contains(&key) {
                        continue;
                    }
                    seen_imports.insert(key.clone());

                    let imported = self.load_module(module_path)?.clone();
                    // Recursively resolve imports in the imported module
                    let resolved = self.resolve_imports(&imported)?;

                    match items {
                        ImportItems::All => {
                            // Import everything (except imports themselves)
                            for d in &resolved.decls {
                                if !matches!(d, Decl::Import { .. }) {
                                    imported_decls.push(d.clone());
                                }
                            }
                        }
                        ImportItems::Specific(items) => {
                            let wanted: HashSet<String> = items.iter().map(|item| {
                                match item {
                                    ImportItem::Value(n) => n.clone(),
                                    ImportItem::TypeAll(n) => n.clone(),
                                    ImportItem::TypeOnly(n) => n.clone(),
                                }
                            }).collect();

                            for d in &resolved.decls {
                                let name = decl_name(d);
                                if let Some(n) = name {
                                    if wanted.contains(&n) {
                                        imported_decls.push(d.clone());
                                    }
                                }
                            }
                        }
                        ImportItems::Qualified(_alias) => {
                            // TODO: qualified imports need name prefixing
                            // For now, import everything
                            for d in &resolved.decls {
                                if !matches!(d, Decl::Import { .. }) {
                                    imported_decls.push(d.clone());
                                }
                            }
                        }
                    }
                }
                _ => {
                    own_decls.push(decl.clone());
                }
            }
        }

        // Merge: imported first, then own
        imported_decls.extend(own_decls);
        Ok(Module { decls: imported_decls })
    }
}

/// Get the primary name of a declaration for import filtering
fn decl_name(decl: &Decl) -> Option<String> {
    match decl {
        Decl::TypeSig { name, .. } => Some(name.clone()),
        Decl::FunDef { name, .. } => Some(name.clone()),
        Decl::DataDef { name, .. } => Some(name.clone()),
        Decl::NewtypeDef { name, .. } => Some(name.clone()),
        Decl::ClassDecl { name, .. } => Some(name.clone()),
        Decl::InstanceDecl { class_name, .. } => Some(class_name.clone()),
        Decl::ExportSig { name, .. } => Some(name.clone()),
        Decl::TypeFamily { name, .. } => Some(name.clone()),
        Decl::Import { .. } => None,
    }
}
