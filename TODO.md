MATA-LL TODO
============

## Specified but not implemented

- [x] User-defined type families (parser skips them)
- [x] Kind checking (Type, Symbol, Fn — specified but not enforced)
- [x] Superclass constraints on instance declarations
- [x] Record field accessors (person.name)
- [x] newtype codegen (zero-cost wrapping)
- [x] Exhaustiveness checking for pattern matches

## Practically useful

- [x] Better error messages (line numbers on type errors)
- [x] where clauses in functions (parsed, codegen incomplete)
- [x] Operator sections: (+1), (1+)
- [x] deriving (auto-generate Show, Eq instances)


## Architectural

- [x] Apply final substitution to TIR (unresolved type vars limit monomorphization)
- [x] Prelude as .mll (now possible with lists and FFI)
