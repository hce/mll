Modest Attempt at Typesystem Augmenting the Lua Language (mata-ll)
==================================================================

| `fib.mll` | `callfib.lua` |
|-----------|---------------|
| <pre>fib :: [Integer]<br>fib = 1:1:zipWith (+) fib (tail fib)<br><br>export fibonacci :: Integer -> [Integer]<br>fibonacci = flip take fib</pre> | <pre>local fib = require "fib"<br><br>local fibs = fib.fibonacci(8)<br>for i, n in ipairs(fibs) do<br>    print(i, n)<br>end</pre> |


## Project goals

If you make a mistake, the compiler is already there to
stop you before any harm can spread to the runtime.

Make available a useful subset of modern haskell to Lua. It is not
intended to be a replacement for haskell, but rather as a way to write
haskell code where you would otherwise write Lua code.

Primary focus is on writing embedded code in a safer way than is
possible with Lua without breaking boundaries to Lua.

Specifically:

* Add the expressiveness, fun and safety of haskell to Lua
* Target the Lua 5.4+ VM; compile to Lua source for safe loading via mlua
* Non-strict evaluation with cheapness analysis (thunk only what's worth thunking)
* No need for a separate runtime, use zero-cost abstractions
* If zero-cost abstractions don't fully work, use library functions
* Incorporate new type system research where possible and useful
* But once a stable version is reached, stay backwards compatible
* Have an easy interface to plain Lua
* Be portable and small; do not incorporate 3rd party rust libraries
* Use rust's versioning for dependency resolving, not haskell's

## What's the difference between a runtime and library functions?

A runtime implements core functionality, while a library provides
auxiliary functionality, still relying on the underlying architecture
for core functionality.

For example, you cannot implement green threads with a library on Lua,
because Lua doesn't have green threads. You can, however, implement
monads with a library on Lua, because Lua does have 1st class
functions and closures (the core building blocks of monads), while it
does not have monads.

## Why rust, not C

While C may seem to be more portable, that is slowly changing: rust is
adding many targets, and for those, keeping C out is making the build
process more robust.

Since I think the combination of rust and Lua is a good one, one of
the primary goals of this project is to make the Lua part a bit 
more statically typed.

I miss writing haskell code but have mostly decided to do production
work in rust. A lot of "business logic" is hard to *write* efficiently
in rust, though, because of rust's focus on memory efficiency. Lua
fills that gap, but haskell could also fill it. However, a full blown
haskell stack has disadvantages:

Huge ecosystem that often experiences "dependency hell";
large dependencies for building, huge binaries generated;
hard to get it to interoperate with rust.

Besides, haskell and its ecosystem offer a full tooling suite, while
Lua is primarily focused on embedding. Using normal haskell would
increase complexity for any project embedding it, which is often not
feasible.

By writing the compiler in rust but targetting the Lua IR, I am hoping
to make it easier to write code that does not require the raw
performance that rust offers in a haskell-like language.

In addition, type safety allows to catch bugs during compile time,
which make development with the help of an LLM much easier.


## Language properties:

File extension should be .mll.

Each .mll file is a module, just like in haskell.

When compiling an .mll file, included .mll files will be merged into
the resulting output .o file.

While the language targets the Lua VM and no additional
runtime is required, there is no need to stay closely compatible otherwise.
Interaction between mll and other Lua functions and modules
happens through well defined interfaces only.

For example, within mll scope, a Lua dictionary can and should be
reused to implement the haskell data construct.

For interacting with non-mll Lua, an FFI interface is provided.
This interface is used both to call into Lua as well as to export
functions to Lua.

## Evaluation strategy

MATA-LL uses non-strict evaluation, like Haskell. Function arguments
and let bindings are not evaluated until their values are needed.
This enables infinite data structures, avoids unnecessary computation,
and makes the language behave as Haskell programmers expect.

To avoid the overhead of thunking cheap expressions (and the classic
space leak in accumulator patterns), the compiler performs cheapness
analysis: expressions that are cheaper to compute than to thunk
(arithmetic, variable references, literals, constructor applications)
are evaluated eagerly. Only genuinely expensive expressions (function
calls, case expressions) are wrapped in memoizing thunks.

For the rare cases where explicit control is needed, `seq :: a -> b -> b`
forces evaluation of its first argument before returning the second.


## Acknowledgements

This project was developed collaboratively by a human and an AI.
The design, direction and taste are Hans-Christian's; much of the
implementation was written by Claude (Anthropic). Neither could have
built it alone -- at least not in a weekend.

## Contributing

By submitting a pull request, you agree to license your contribution
under the MIT License, the same license that covers this project.

## Dependencies

So far, no dependencies (MLL libraries) are supported. I don't think
that's a primary scope for now. But once support is added, they should
be resolved in the rust way. Conflicting transitive dependencies must
not let a build fail; rather, version numbers should be part of the
internal symbols, so that an arbitrary number of conflicting versions
can coexist in parallel.


