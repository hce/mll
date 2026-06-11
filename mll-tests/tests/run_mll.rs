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
mll_test!(either_ordering, "either_ordering.mll");
mll_test!(dict, "dict.mll");
mll_test!(hashmap, "hashmap.mll");
mll_test!(gadts, "gadts.mll");
mll_test!(tuples, "tuples.mll");
mll_test!(trees, "trees.mll");
mll_test!(mutual_recursion, "mutual_recursion.mll");
mll_test!(higher_order, "higher_order.mll");
mll_test!(fizzbuzz, "fizzbuzz.mll");
mll_test!(purehashmap, "purehashmap.mll");

// Compile-error tests: these SHOULD fail to compile
#[test]
fn eq_without_instance_rejected() {
    let source = r#"
data Foo = Foo
    deriving Show

main :: IO ()
main = putStrLn (show (Foo == Foo))
"#;
    match mllc::compile(source, Path::new("."), &[]) {
        Err(e) => {
            let msg = format!("{}", e);
            assert!(msg.contains("No instance"), "Expected 'No instance' error, got: {}", msg);
        }
        Ok(_) => panic!("Expected compilation to fail for == without Eq instance"),
    }
}

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

#[test]
fn orphan_instance_rejected() {
    // Show and Integer are both defined in the prelude, not locally.
    // Defining an instance for them here is an orphan instance.
    let source = r#"
instance Show Integer where
    show x = "int"

main :: IO ()
main = putStrLn "ok"
"#;
    match mllc::compile(source, Path::new("."), &[]) {
        Err(e) => {
            let msg = format!("{}", e);
            assert!(msg.contains("Orphan instance"), "Expected 'Orphan instance' error, got: {}", msg);
        }
        Ok(_) => panic!("Expected compilation to fail for orphan instance"),
    }
}

// Examples that should compile successfully
#[test]
fn examples_compile() {
    let lib_path = Path::new("../lib");
    let examples_dir = Path::new("../examples");

    // Examples expected to fail or skip
    let expected_fail: Vec<&str> = vec![
        "bench",              // show specialization gap on list display
        "regex_test",         // deep typechecker recursion on CPS types needs larger stack
        "jsontest",           // deep typechecker recursion on imported JSON module
        "aestest",            // 256-element S-box lists need large stack (runs via mll compiler)
    ];

    let mut failures = Vec::new();
    for entry in std::fs::read_dir(examples_dir).expect("Cannot read examples/") {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().map_or(true, |e| e != "mll") {
            continue;
        }
        let stem = path.file_stem().unwrap().to_str().unwrap();
        if expected_fail.contains(&stem) {
            continue;
        }
        let source = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("Cannot read {}: {}", path.display(), e));
        let source_dir = path.parent().unwrap_or(Path::new("."));
        match mllc::compile(&source, source_dir, &[lib_path]) {
            Ok(_) => {}
            Err(e) => failures.push(format!("{}: {}", stem, e)),
        }
    }
    if !failures.is_empty() {
        panic!("Examples failed to compile:\n{}", failures.join("\n"));
    }
}
