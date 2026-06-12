# DESIGN

Design notes for mata-ll. This document describes what *is* and how it is
achieved, as opposed to SPEC.md which describes what *should be*.

## Record backing store

Records are backed by plain Lua tables with integer keys matching constructor
field order. These tables are created and consumed exclusively by mata-ll
generated code; plain Lua does not interact with them directly.

### Record update (not yet implemented)

Record update syntax (`foo { x = 3 }`) requires producing a new table that
shares all fields with the original except the updated ones. This should be a
**shallow copy**: iterate the table slots and patch the changed fields.

A shallow copy is correct because:

- Field values are either Lua primitives, references to other mata-ll values
  (tables/thunks), or thunks. These are all safe to share by reference.
- A deep clone would be wrong: it would force thunks prematurely or duplicate
  shared structure, breaking both laziness and identity semantics.
- The tables are exclusively managed by mata-ll, so there is no risk of
  external mutation violating the immutability invariant.

Cost is O(n) in the number of fields per update, which is acceptable for
typical record sizes.
