Regression in incomplete_tag
On JuliaSyntax master:
```
julia> s = "CompletionFoo.test(1, 1, "
"CompletionFoo.test(1, 1, "

julia> Base.incomplete_tag(Meta.parse(s, raise=false, depwarn=false))
:none
```
vs Base:
```
julia> Base.incomplete_tag(Meta.parse(s, raise=false, depwarn=false))
:other
```

I looked into adjusting the tag selector a bit, but couldn't come up with a good version that also distinguished `[x ` (with space), `[x)` and `(` and `( `, so there may need to be some adjustment to the source-location representation itself. @c42f can you take a look?

### Additional contract requirements

For the examples `[x `, `[x)`, `(`, and `( `, tag selection must preserve the distinction between incomplete input and non-incomplete input: `[x `, `(`, and `( ` are incomplete, whereas `[x)` is not and must have the `:none` tag. The forms `[x ` and `( ` must have a non-`:none` tag, without prescribing a particular symbol. The form `(` continues to have the `:other` tag.

For `CompletionFoo.test(1, 1, `, `Base.incomplete_tag(Meta.parse(s, raise=false, depwarn=false))` must return `:other`.
