MATA-LL TODO
============

## Completed

- [x] Record field accessors (person.name)
- [x] newtype codegen (zero-cost wrapping)
- [x] Exhaustiveness checking for pattern matches
- [x] Better error messages (line numbers on type errors)
- [x] where clauses in functions
- [x] Operator sections: (+1), (1+)
- [x] deriving (auto-generate Show, Eq instances)
- [x] Apply final substitution to TIR
- [x] Prelude as .mll
- [x] User-defined type families
- [x] Kind checking (Type, Symbol, Fn)
- [x] Superclass constraints on instance declarations
- [x] Either, Ordering types in prelude
- [x] Show instance enforcement
- [x] Mutual recursion support
- [x] Composition codegen fix
- [x] GADTs (full pipeline: parser, type checker, exhaustiveness, codegen)
- [x] Non-strict evaluation with cheapness analysis
- [x] seq :: a -> b -> b (explicit forcing)
- [x] Guards in where-clause bindings
- [x] Do-notation: break on closing paren
- [x] __mll_run for IO thunk forcing in >>=

## Typeclasses and dispatch

- [x] Eq as a proper typeclass gating == and /=
- [x] Ord as a proper typeclass gating <, >, <=, >=
- [x] Monad typeclass and >>= operator
- [x] Desugar do-notation through >>= instead of hardwiring

## Missing types and values

- [x] HashMap k v (intrinsic dictionary type, backed by Lua tables)
- [x] Any type (Lua interop: String | Integer | Number | Bool | Null | ...)
- [x] getArgs :: IO [String]
- [x] exit :: IO ExitValue (data ExitValue = Normal | Err Integer)

## Language features

- [x] Record construction with named fields: Person { perName = "Morpheus" }
- [x] Qualified import name prefixing (import qualified Data.Tree as T)
- [x] Polymorphic recursion detection (specialization depth limit)
- [x] Expression type ascription (expr :: Type)
- [x] Orphan instance detection
- [x] Process intrinsic declarations properly
- [x] when (now feasible with non-strict evaluation)
- [x] Concrete variable tracking to skip redundant __force calls

## Can defer (spec says so)

- [ ] Operator fixity declarations (Haskell defaults hardcoded)
- [ ] Lambda pattern matching
- [ ] FFI varargs support for Lua functions like string.format
