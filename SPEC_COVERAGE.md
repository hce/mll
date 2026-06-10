## Spec coverage

The compiler covers roughly 85% of the SPEC. Below is a detailed
breakdown of what is implemented and what is still open.

### Types and data

| Feature | Status |
|---------|--------|
| Primitive types (String, Integer, Number, Bool) | Done |
| Lists [a] (cons-cell) | Done |
| ADTs with multiple constructors | Done |
| Single-variant optimization (no tag) | Done |
| Enum optimization (integer tag) | Done |
| Record syntax (named fields, accessors, dot syntax) | Done |
| Record construction with named fields | Done |
| Newtype (zero-cost wrapping) | Done |
| Maybe (Just, Nothing) | Done |
| Either (Left, Right) | Done |
| Ordering (LT, EQ, GT) | Done |
| Any (Lua interop type) | Done |
| HashMap k v | Done |
| GADTs | Done |

### Typeclasses

| Feature | Status |
|---------|--------|
| Single-parameter typeclasses | Done |
| Typeclass instances | Done |
| Superclass constraints | Done |
| Show (built-in + deriving) | Done |
| Eq (built-in + deriving, gates ==) | Done |
| Ord (built-in, gates <, >, <=, >=) | Done |
| Monomorphization dispatch | Done |
| Orphan instance detection | Not yet |
| Functor / Applicative / Monad hierarchy | Not yet |

### Type system

| Feature | Status |
|---------|--------|
| Hindley-Milner unification | Done |
| Top-level signatures required | Done |
| Sub-expression inference | Done |
| User-defined type families | Done |
| Kind checking (Type, Symbol, Fn) | Done |
| Expression type ascription (expr :: Type) | Done |
| Exhaustiveness checking (GADT-aware) | Done |
| Polymorphic recursion detection | Done |
| GADTs (per-constructor return types) | Done |

### Evaluation strategy

| Feature | Status |
|---------|--------|
| Non-strict evaluation (thunked arguments) | Done |
| Memoizing thunks (force-once) | Done |
| Cheapness analysis (skip thunking for arithmetic, vars, literals) | Done |
| Selective forcing (only destructured pattern args forced at entry) | Done |
| seq :: a -> b -> b (explicit forcing) | Done |
| Infinite structures (lazy cons) | Done |

### Functions and expressions

| Feature | Status |
|---------|--------|
| Multi-argument functions | Done |
| Partial application | Done |
| Pattern matching (functions, case, guards) | Done |
| Lambda expressions | Done |
| Let/in expressions | Done |
| Where clauses (values and local functions) | Done |
| Do-notation | Done (hardwired) |
| If/then/else | Done |
| Operator sections (+1), (1+) | Done |
| Operators as functions (+) | Done |
| Backtick infix | Done |
| Function composition (.) | Done |
| Mutual recursion | Done |

### FFI and interop

| Feature | Status |
|---------|--------|
| LuaPure FFI (pure Lua calls) | Done |
| LuaIO FFI (effectful Lua calls) | Done |
| LuaFunction s (opaque Lua callbacks) | Done |
| engage (type Lua callbacks) | Done |
| Scope safety via forall s. | Done |
| liftIO (IO to LuaIO) | Done |
| Export declarations | Done |
| FFI varargs | Not yet |

### Prelude and standard library

| Feature | Status |
|---------|--------|
| Prelude as .mll (type-checked) | Done |
| id, const, flip | Done |
| map, filter, foldl, foldr | Done |
| head, tail, take, reverse, length | Done |
| zipWith | Done |
| putStrLn, show, error | Done |
| sqrt, max, min | Done |
| getArgs, exit | Done |
| assert (for testing) | Done |

### Modules and imports

| Feature | Status |
|---------|--------|
| import Module | Done |
| import Module (specific items) | Done |
| import qualified Module as Alias | Done |
| Module search paths (-L flag) | Done |

### Compiler quality

| Feature | Status |
|---------|--------|
| Line numbers in error messages | Done |
| Type mismatch errors with context | Done |
| Kind errors | Done |
| Missing instance errors | Done |
| Non-exhaustive pattern warnings | Done |
| Test suite (24 .mll test files) | Done |

### Not yet implemented

| Feature | Effort | Notes |
|---------|--------|-------|
| Functor/Applicative/Monad + do desugaring | Hard | Do-notation works fine without |
| Orphan instance detection | Low | Multi-module correctness |
| Process intrinsic declarations | Medium | Spec completeness |
| when | Low | Now feasible with non-strict evaluation |
| Operator fixity declarations | Medium | Spec explicitly defers |
| Lambda pattern matching | Medium | Spec explicitly defers |
| FFI varargs | Medium | For Lua functions like string.format |
