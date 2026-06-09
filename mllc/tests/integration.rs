/// Integration tests for the MLL compiler.
///
/// Each test compiles a snippet of MLL source and either:
/// - checks that compilation succeeds (compile_ok)
/// - checks that compilation fails with a specific error (compile_err)
/// - checks that the generated Lua contains expected patterns (compile_check)

use std::path::Path;

fn compile(source: &str) -> Result<mllc::CompileResult, mllc::CompileError> {
    mllc::compile(source, Path::new("."), &[])
}

fn compile_ok(source: &str) -> String {
    match compile(source) {
        Ok(r) => r.lua_code,
        Err(e) => panic!("Expected compilation to succeed, but got:\n{}", e),
    }
}

fn compile_err(source: &str) -> String {
    match compile(source) {
        Ok(_) => panic!("Expected compilation to fail, but it succeeded"),
        Err(e) => format!("{}", e),
    }
}

// ============================================================
// Basic programs
// ============================================================

#[test]
fn hello_world() {
    let lua = compile_ok(r#"
main :: IO ()
main = putStrLn "Hello, World!"
"#);
    assert!(lua.contains("putStrLn(\"Hello, World!\")"));
}

#[test]
fn simple_function() {
    compile_ok(r#"
add :: Integer -> Integer -> Integer
add a b = a + b

main :: IO ()
main = putStrLn (show (add 1 2))
"#);
}

#[test]
fn if_then_else() {
    compile_ok(r#"
abs' :: Integer -> Integer
abs' n = if n < 0 then 0 - n else n

main :: IO ()
main = putStrLn (show (abs' (-5)))
"#);
}

// ============================================================
// Type errors
// ============================================================

#[test]
fn type_mismatch_in_function() {
    let err = compile_err(r#"
add :: Integer -> Integer -> Integer
add a b = a ++ b

main :: IO ()
main = putStrLn (show (add 1 2))
"#);
    assert!(err.contains("Cannot unify"));
    assert!(err.contains("String"));
    assert!(err.contains("Integer"));
}

#[test]
fn type_mismatch_in_application() {
    let err = compile_err(r#"
main :: IO ()
main = putStrLn 42
"#);
    assert!(err.contains("Cannot unify"));
}

#[test]
fn unbound_variable() {
    let err = compile_err(r#"
main :: IO ()
main = putStrLn (show (foo 1))
"#);
    assert!(err.contains("Unbound variable"));
    assert!(err.contains("foo"));
}

#[test]
fn missing_type_signature() {
    let err = compile_err(r#"
add a b = a + b

main :: IO ()
main = putStrLn "hello"
"#);
    assert!(err.contains("Missing type signature"));
}

// ============================================================
// Line numbers in errors
// ============================================================

#[test]
fn error_has_line_number() {
    let err = compile_err(r#"
bad :: Integer -> Integer
bad x = x ++ "hello"

main :: IO ()
main = putStrLn (show (bad 1))
"#);
    assert!(err.contains("at "));
    assert!(err.contains("in definition of 'bad'"));
}

// ============================================================
// Data types and pattern matching
// ============================================================

#[test]
fn data_type_basic() {
    compile_ok(r#"
data Color = Red | Green | Blue

name :: Color -> String
name Red = "red"
name Green = "green"
name Blue = "blue"

main :: IO ()
main = putStrLn (name Red)
"#);
}

#[test]
fn data_type_with_fields() {
    compile_ok(r#"
data Shape = Circle Number | Rect Number Number

area :: Shape -> Number
area (Circle r) = 3.14 * r * r
area (Rect w h) = w * h

main :: IO ()
main = putStrLn (show (area (Circle 5.0)))
"#);
}

#[test]
fn case_expression() {
    compile_ok(r#"
data Color = Red | Green | Blue

colorName :: Color -> String
colorName c = case c of
    Red -> "red"
    Green -> "green"
    Blue -> "blue"

main :: IO ()
main = putStrLn (colorName Red)
"#);
}

// ============================================================
// Exhaustiveness checking
// ============================================================

#[test]
fn exhaustive_patterns_ok() {
    compile_ok(r#"
data AB = A | B

f :: AB -> String
f A = "a"
f B = "b"

main :: IO ()
main = putStrLn (f A)
"#);
}

#[test]
fn non_exhaustive_function() {
    let err = compile_err(r#"
data AB = A | B

f :: AB -> String
f A = "a"

main :: IO ()
main = putStrLn (f A)
"#);
    assert!(err.contains("Non-exhaustive"));
    assert!(err.contains("B"));
}

#[test]
fn non_exhaustive_case() {
    let err = compile_err(r#"
data AB = A | B

f :: AB -> String
f x = case x of
    A -> "a"

main :: IO ()
main = putStrLn (f A)
"#);
    assert!(err.contains("Non-exhaustive"));
    assert!(err.contains("B"));
}

#[test]
fn wildcard_is_exhaustive() {
    compile_ok(r#"
data AB = A | B

f :: AB -> String
f A = "a"
f _ = "other"

main :: IO ()
main = putStrLn (f A)
"#);
}

// ============================================================
// Lists
// ============================================================

#[test]
fn list_construction() {
    compile_ok(r#"
main :: IO ()
main = putStrLn (show [1, 2, 3])
"#);
}

#[test]
fn list_pattern_matching() {
    compile_ok(r#"
sum' :: [Integer] -> Integer
sum' [] = 0
sum' (x:xs) = x + sum' xs

main :: IO ()
main = putStrLn (show (sum' [1, 2, 3, 4, 5]))
"#);
}

#[test]
fn list_prelude_functions() {
    compile_ok(r#"
main :: IO ()
main = do
    putStrLn (show (map (+1) [1, 2, 3]))
    putStrLn (show (filter (>2) [1, 2, 3, 4, 5]))
    putStrLn (show (foldl (+) 0 [1, 2, 3, 4, 5]))
    putStrLn (show (length [1, 2, 3]))
    putStrLn (show (take 2 [1, 2, 3, 4]))
    putStrLn (show (reverse [1, 2, 3]))
"#);
}

// ============================================================
// Records and dot syntax
// ============================================================

#[test]
fn record_construction_and_access() {
    compile_ok(r#"
data Person = Person { personName :: String, personAge :: Integer }

main :: IO ()
main = do
    let p = Person "Alice" 30
    putStrLn (personName p)
    putStrLn (show (personAge p))
"#);
}

#[test]
fn record_dot_syntax() {
    compile_ok(r#"
data Person = Person { personName :: String, personAge :: Integer }

main :: IO ()
main = do
    let p = Person "Alice" 30
    putStrLn p.personName
    putStrLn (show p.personAge)
"#);
}

#[test]
fn dot_vs_composition() {
    // Ensure dot-access doesn't break function composition
    compile_ok(r#"
main :: IO ()
main = do
    let xs = [1, 2, 3]
    (putStrLn . show) xs
"#);
}

// ============================================================
// Newtypes
// ============================================================

#[test]
fn newtype_basic() {
    let lua = compile_ok(r#"
newtype Age = Integer

mkAge :: Integer -> Age
mkAge x = Age x

getAge :: Age -> Integer
getAge (Age x) = x

main :: IO ()
main = putStrLn (show (getAge (mkAge 42)))
"#);
    // Constructor should be identity
    assert!(lua.contains("function Age(_v) return _v end"));
}

// ============================================================
// Typeclasses
// ============================================================

#[test]
fn typeclass_basic() {
    compile_ok(r#"
class Describe a where
    describe :: a -> String

data Color = Red | Blue

instance Describe Color where
    describe Red = "the color red"
    describe Blue = "the color blue"

main :: IO ()
main = putStrLn (describe Red)
"#);
}

#[test]
fn deriving_show() {
    compile_ok(r#"
data Color = Red | Green | Blue
    deriving Show

main :: IO ()
main = do
    putStrLn (show Red)
    putStrLn (show Green)
    putStrLn (show Blue)
"#);
}

#[test]
fn deriving_eq() {
    compile_ok(r#"
data Color = Red | Green | Blue
    deriving (Show, Eq)

main :: IO ()
main = do
    putStrLn (show (Red == Red))
    putStrLn (show (Red == Blue))
"#);
}

#[test]
fn superclass_constraint_enforced() {
    let err = compile_err(r#"
class Eq a where
    (==) :: a -> a -> Bool

class Eq a => Ord a where
    compare :: a -> a -> Integer

data Foo = Foo

instance Ord Foo where
    compare Foo Foo = 0

main :: IO ()
main = putStrLn "hello"
"#);
    assert!(err.contains("superclass"));
    assert!(err.contains("Eq"));
}

#[test]
fn superclass_constraint_satisfied() {
    compile_ok(r#"
class Eq a where
    (==) :: a -> a -> Bool

class Eq a => Ord a where
    compare :: a -> a -> Integer

data Foo = Foo
    deriving Eq

instance Ord Foo where
    compare Foo Foo = 0

main :: IO ()
main = putStrLn (show (compare Foo Foo))
"#);
}

// ============================================================
// Where clauses
// ============================================================

#[test]
fn where_simple_binding() {
    compile_ok(r#"
tripled :: Integer -> Integer
tripled x = result
    where result = x + x + x

main :: IO ()
main = putStrLn (show (tripled 7))
"#);
}

#[test]
fn where_local_function() {
    compile_ok(r#"
sumList :: [Integer] -> Integer
sumList xs = go 0 xs
    where
        go acc [] = acc
        go acc (x:rest) = go (acc + x) rest

main :: IO ()
main = putStrLn (show (sumList [1, 2, 3, 4, 5]))
"#);
}

// ============================================================
// Operator sections
// ============================================================

#[test]
fn right_section() {
    compile_ok(r#"
main :: IO ()
main = putStrLn (show (map (+1) [1, 2, 3]))
"#);
}

#[test]
fn left_section() {
    compile_ok(r#"
main :: IO ()
main = putStrLn (show (map (10-) [1, 2, 3]))
"#);
}

#[test]
fn section_as_value() {
    compile_ok(r#"
main :: IO ()
main = do
    let double = (*2)
    putStrLn (show (double 21))
"#);
}

#[test]
fn negation_not_section() {
    // (-5) should be negation, not a subtract section
    compile_ok(r#"
main :: IO ()
main = putStrLn (show (-5))
"#);
}

// ============================================================
// Monomorphization
// ============================================================

#[test]
fn polymorphic_function_specialized() {
    compile_ok(r#"
twice :: (a -> a) -> a -> a
twice f x = f (f x)

main :: IO ()
main = do
    putStrLn (show (twice (+1) 5))
    putStrLn (twice (++"!") "hello")
"#);
}

// ============================================================
// Guards
// ============================================================

#[test]
fn guards_basic() {
    compile_ok(r#"
classify :: Integer -> String
classify n
    | n < 0     = "negative"
    | n == 0    = "zero"
    | otherwise = "positive"

main :: IO ()
main = do
    putStrLn (classify (-1))
    putStrLn (classify 0)
    putStrLn (classify 1)
"#);
}

#[test]
fn guards_with_patterns() {
    compile_ok(r#"
safeDiv :: Integer -> Integer -> String
safeDiv _ 0 = "division by zero"
safeDiv a b = show (a / b)

main :: IO ()
main = do
    putStrLn (safeDiv 10 2)
    putStrLn (safeDiv 10 0)
"#);
}

// ============================================================
// Lambda expressions
// ============================================================

#[test]
fn lambda_basic() {
    compile_ok(r#"
main :: IO ()
main = do
    let f = \x -> x + 1
    putStrLn (show (f 5))
"#);
}

#[test]
fn lambda_multi_param() {
    compile_ok(r#"
main :: IO ()
main = do
    let add = \x y -> x + y
    putStrLn (show (add 3 4))
"#);
}

// ============================================================
// Do notation
// ============================================================

#[test]
fn do_bind() {
    compile_ok(r#"
main :: IO ()
main = do
    let x = 42
    putStrLn (show x)
"#);
}

#[test]
fn do_sequence() {
    compile_ok(r#"
main :: IO ()
main = do
    putStrLn "first"
    putStrLn "second"
    putStrLn "third"
"#);
}

// ============================================================
// FFI
// ============================================================

#[test]
fn ffi_pure() {
    compile_ok(r#"
sin :: Number -> LuaPure "math.sin" Number

main :: IO ()
main = putStrLn (show (sin 0.5))
"#);
}

#[test]
fn ffi_io() {
    compile_ok(r#"
random :: Number -> Number -> LuaIO "math.random" Number

main :: IO ()
main = do
    r <- random 1.0 10.0
    putStrLn (show r)
"#);
}

// ============================================================
// Type families
// ============================================================

#[test]
fn type_family_basic() {
    compile_ok(r#"
type family Element container where
    Element [a] = a

head' :: [a] -> Element [a]
head' (x:_) = x
head' [] = error "empty"

main :: IO ()
main = putStrLn (show (head' [42]))
"#);
}

// ============================================================
// Kind checking
// ============================================================

#[test]
fn kind_error_type_applied() {
    let err = compile_err(r#"
bad :: Integer String -> Bool
bad _ = True

main :: IO ()
main = putStrLn "hello"
"#);
    assert!(err.contains("Kind error"));
    assert!(err.contains("Integer"));
}

// ============================================================
// Let expressions
// ============================================================

#[test]
fn let_in_expression() {
    compile_ok(r#"
main :: IO ()
main = putStrLn (show (let x = 5 in x + x))
"#);
}

// ============================================================
// Maybe
// ============================================================

#[test]
fn maybe_just_nothing() {
    compile_ok(r#"
fromMaybe :: a -> Maybe a -> a
fromMaybe def Nothing = def
fromMaybe _ (Just x) = x

main :: IO ()
main = do
    putStrLn (show (fromMaybe 0 (Just 42)))
    putStrLn (show (fromMaybe 0 Nothing))
"#);
}

// ============================================================
// Infix operators
// ============================================================

#[test]
fn dollar_operator() {
    compile_ok(r#"
main :: IO ()
main = putStrLn $ show $ 1 + 2
"#);
}

#[test]
fn backtick_infix() {
    compile_ok(r#"
add :: Integer -> Integer -> Integer
add a b = a + b

main :: IO ()
main = putStrLn (show (3 `add` 4))
"#);
}

// ============================================================
// String operations
// ============================================================

#[test]
fn string_concatenation() {
    compile_ok(r#"
main :: IO ()
main = putStrLn ("Hello, " ++ "World!")
"#);
}

// ============================================================
// Exports
// ============================================================

#[test]
fn export_declaration() {
    let result = compile(r#"
add :: Integer -> Integer -> Integer
add a b = a + b

export add :: Integer -> Integer -> Integer
"#).unwrap();
    assert!(result.exports.contains(&"add".to_string()));
}
