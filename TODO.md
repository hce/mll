MATA-LL TODO
============

## Specified but not implemented

- [ ] User-defined type families (parser skips them)
- [ ] Kind checking (Type, Symbol, Fn — specified but not enforced)
- [ ] Superclass constraints on instance declarations
- [x] Record field accessors (person.name)
- [ ] newtype codegen (zero-cost wrapping)
- [x] Exhaustiveness checking for pattern matches

## Practically useful

- [x] Better error messages (line numbers on type errors)
- [x] where clauses in functions (parsed, codegen incomplete)
- [ ] Operator sections: (+1), (1+)
- [x] deriving (auto-generate Show, Eq instances)
- [ ] Lua bytecode output (the spec's ultimate goal)

## Architectural

- [x] Apply final substitution to TIR (unresolved type vars limit monomorphization)
- [ ] Prelude as .mll (now possible with lists and FFI)
