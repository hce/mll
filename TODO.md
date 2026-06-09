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

## Typeclasses and dispatch

- [x] Eq as a proper typeclass gating == and /=
- [x] Ord as a proper typeclass gating <, >, <=, >=
- [ ] Functor / Applicative / Monad hierarchy (spec lines 370-388)
- [ ] Desugar do-notation through >>= instead of hardwiring

## Missing types and values

- [ ] HashMap k v (intrinsic dictionary type)
- [x] Any type (Lua interop: String | Integer | Number | Bool | Null | ...)
- [x] getArgs :: IO [String]
- [x] exit :: IO ExitValue (data ExitValue = Normal | Err Integer)

## Language features

- [ ] GADTs (parser recognizes syntax, type checker discards type info)
- [x] Record construction with named fields: Person { perName = "Morpheus" }
- [x] Qualified import name prefixing (import qualified Data.Tree as T)
- [ ] Orphan instance detection
- [x] Polymorphic recursion detection (specialization depth limit)
- [ ] Process intrinsic declarations properly
- [x] Expression type ascription (expr :: Type)
- [ ] when (needs lazy IO or thunked actions)

## Can defer (spec says so)

- [ ] Operator fixity declarations (Haskell defaults hardcoded)
- [ ] Lambda pattern matching
- [ ] FFI varargs support for Lua functions like string.format
