Tracker performance TODO
========================

"All function parameters are forced once at entry and marked concrete, eliminating repeated __force calls throughout the body"
 -- I think this one breaks some important semantics, such as implementing custom if blocks

"Monadic bind continuations (>>= with a lambda) mark their parameters concrete, since __mll_run always produces a forced value."
 -- This, too, may break things. What about, for example: "expensivePureComputation <$> getLine :: IO SomeResult"?


Current: 121s of audio rendered in 315s (2.6× slower than real-time).
Target: real-time on commodity hardware.

## Prelude runtime functions as concrete

`__mll_ma_read`, `__mll_ma_write`, `return_`, etc. are Prelude
runtime locals — always plain functions, never thunks. The codegen
should seed `concrete_vars` with all Prelude runtime names so
references skip `__force`. Currently 8 `__force(__mll_ma_read)` calls
per channel per frame in the inner mixing loop (~140M unnecessary
`getmetatable` checks across the full song).

## If-expressions as statements in bind chains

Inside a flattened do-block, `let` bindings whose body is an `if`
expression generate IIFEs:

    local smp = (function()
        if (smpPos < sl) then return readSmp(...) else return 0 end
    end)()

These should emit as Lua if/then/else statements instead:

    local smp
    if (smpPos < sl) then smp = readSmp(...) else smp = 0 end

Eliminates two closure allocations per channel per frame (`smp` and
`sv` calculations in `mixFrame`).

## Inline small pure functions

`fi(ch, fiVol)` compiles to a Lua function call (`fi(ch, fiVol)`)
that computes `ch * 14 + fiVol`. Inlining known-small pure functions
at call sites would eliminate the function call overhead entirely.
