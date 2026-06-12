# Caveats

## Out-of-bounds errors surface as cryptic Lua messages

Lua does not perform bounds checking on string access — `string.byte(s, i)`
returns `nil` when `i` is out of range rather than raising an error. This means
that an out-of-bounds read in mata-ll (e.g. calling `getU16LE` at the last byte
of a ByteString) will not produce a clear "index out of bounds" message.
Instead, the `nil` propagates until it hits an arithmetic operation, resulting
in errors like:

    attempt to perform arithmetic on local 'hi' (a nil value)

Adding bounds checks to the ByteString primitives would fix the messages but
degrade performance for all callers, so this is left as-is. When you see
`attempt to perform arithmetic on … (a nil value)` in compiled output, suspect
an out-of-bounds ByteString access in the source.
