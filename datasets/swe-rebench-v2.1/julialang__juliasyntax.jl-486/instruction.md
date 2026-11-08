`char_range()` function for indexing into source strings
We have a crash from the VS Code extension that seems to originate from JuliaSyntax. Repo steps are:
1. `pkg> dev Sunny`
2. Run
```julia
using JuliaSyntax

src = read(joinpath(homedir(), ".julia/dev/Sunny/test/test_tensors.jl"), String)

tree = parseall(SyntaxNode, src, filename="foo.jl")

i = JuliaSyntax.last_byte(tree[2][end][end])

src[i]
```

That crashes with
```
ERROR: StringIndexError: invalid index [2142], valid nearby indices [2140]=>'′', [2143]=>'\r'
```

I assume that `last_byte` should always return a valid index, right? So this seems like a bug.

The rest of this issue is some speculation from my end, might all be wrong :)

I started looking a bit around in the JuliaSyntax code, and there seems to be a fair bit of code that assumes 1-byte characters, which strikes me as incorrect? Or maybe this is carefully only done when there is a guarantee that only 1-byte codepoints can appear? An example is https://github.com/JuliaLang/JuliaSyntax.jl/blob/1d950817b8ab62a3be2464f4d5b097aa68c17042/src/parse_stream.jl#L519 Doesn't that (incorrectly) assume that the character at index position `last_byte` is only one code unit? Generally if I search the repo for `- 1` or `+ 1` I see a fair bit of code where I would have assumed that a `prevind` or `nextind` would be needed?

### Additional contract requirements

- Add a public function `char_range(x)` in module `JuliaSyntax`. For a syntax object `x` that belongs to a parsed source, it returns an `AbstractUnitRange{Int}` giving the 1-based character indices of the source text covered by `x`. This is the character-index counterpart of the existing `byte_range(x)`: indexing the source string with the returned range yields the source text of `x` even when that text contains multi-byte Unicode characters.
