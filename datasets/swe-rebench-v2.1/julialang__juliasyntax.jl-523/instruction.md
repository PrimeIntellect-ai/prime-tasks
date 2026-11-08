Remap operator tokens to `K"Identifier"` during parsing
Having various operator token kinds is relevant during parsing, but they should potentially all be remapped to `K"Identifier"` afterward because their special status as operators is no longer meaningful once they live in the parse tree - they are essentially just identifiers which will be looked up with the usual scoping rules, just like any other identifier.

Code which processes syntax trees often has to do things like `is_operator(x) || kind(x) == K"Identifier"`. Mapping them to identifiers simplifies things and fixes this issue. For the same reasons, I've also wished for this in JuliaLowering.jl.

One caveat is that this change might be unhelpful for the `JuliaSyntax.tokenize()` API - need to think about what to do there.  (Perhaps operator kinds should be preserved in that case?)

If we do this, we should also do it systematically. For example, to fix https://github.com/JuliaLang/JuliaSyntax.jl/pull/456/files#r1692517031
