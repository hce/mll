/// Test harness: discovers all .mll files in tests/cases/,
/// compiles each with mllc, runs the result via mlua,
/// and reports success/failure.

use std::path::Path;

fn run_mll_file(path: &Path) {
    let source = std::fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("Cannot read {}: {}", path.display(), e));

    let source_dir = path.parent().unwrap_or(Path::new("."));
    let lua_code = match mllc::compile(&source, source_dir, &[]) {
        Ok(r) => r.lua_code,
        Err(e) => panic!("{}: compilation failed:\n{}", path.display(), e),
    };

    let lua = mlua::Lua::new();
    match lua.load(&lua_code).set_name(path.to_str().unwrap()).exec() {
        Ok(()) => {}
        Err(e) => panic!("{}: runtime error:\n{}", path.display(), e),
    }
}

macro_rules! mll_test {
    ($name:ident, $file:expr) => {
        #[test]
        fn $name() {
            run_mll_file(Path::new(concat!("tests/cases/", $file)));
        }
    };
}

mll_test!(basics, "basics.mll");
mll_test!(lists, "lists.mll");
mll_test!(data_types, "data_types.mll");
mll_test!(records, "records.mll");
mll_test!(newtypes, "newtypes.mll");
mll_test!(typeclasses, "typeclasses.mll");
mll_test!(superclass, "superclass.mll");
mll_test!(where_clauses, "where_clauses.mll");
mll_test!(operator_sections, "operator_sections.mll");
mll_test!(guards, "guards.mll");
mll_test!(lambdas, "lambdas.mll");
mll_test!(maybe, "maybe.mll");
mll_test!(monomorphization, "monomorphization.mll");
mll_test!(strings, "strings.mll");
mll_test!(operators, "operators.mll");
mll_test!(let_exprs, "let_exprs.mll");
mll_test!(ffi, "ffi.mll");
mll_test!(show_required, "show_required.mll");

// Compile-error tests: these SHOULD fail to compile
#[test]
fn show_without_instance_rejected() {
    let source = r#"
data Secret = Secret Integer

main :: IO ()
main = putStrLn (show (Secret 42))
"#;
    match mllc::compile(source, Path::new("."), &[]) {
        Err(e) => {
            let msg = format!("{}", e);
            assert!(msg.contains("No instance"), "Expected 'No instance' error, got: {}", msg);
        }
        Ok(_) => panic!("Expected compilation to fail for show without Show instance"),
    }
}
