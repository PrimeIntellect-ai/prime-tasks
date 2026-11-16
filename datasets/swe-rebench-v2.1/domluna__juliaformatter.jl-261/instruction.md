`{1; 2; 3}` is formatted to `{123}`
```julia
julia> txt = "{1; 2; 3}"
"{1; 2; 3}"

julia> format_text(txt)
"{123}"

julia> Meta.parse(txt)
:({1; 2; 3})

julia> Meta.parse(format_text(txt))
:({123})

(tmp9_o3s8jg.julia_tmp) pkg> st -m
Status `/tmp/tmp9_o3s8jg.julia_tmp/Manifest.toml`
  [00ebfdb7] CSTParser v2.5.0
  [864edb3b] DataStructures v0.17.19
  [98e50ef6] JuliaFormatter v0.6.6
  [bac558e1] OrderedCollections v1.3.0
  [0796e94c] Tokenize v0.5.8
  [2a0f44e3] Base64
  [ade2ca70] Dates
  [8ba89e20] Distributed
  [b77e0a4c] InteractiveUtils
  [76f85450] LibGit2
  [8f399da3] Libdl
  [56ddb016] Logging
  [d6f4376e] Markdown
  [44cfe95a] Pkg
  [de0858da] Printf
  [3fa0cd96] REPL
  [9a3f8284] Random
  [ea8e919c] SHA
  [9e88b42a] Serialization
  [6462fe0b] Sockets
  [8dfed614] Test
  [cf7118a7] UUIDs
  [4ec0a83e] Unicode
```

### Additional contract requirements

- With `fmt(text, margin, offset)`, `fmt("{1; 2; 3}", 2, length("{1; 2; 3}") - 1)` must return `"{\n  1;\n  2;\n  3;\n}"`, and `fmt("{\n  1;\n  2;\n  3;\n}", 2, length("{1; 2; 3}"))` must return `"{1; 2; 3}"`.
- With `fmt(text, margin, offset)`, `fmt("{1; 2; 3}", 4, length("{1; 2; 3}"))` must return `"{1; 2; 3}"`.
