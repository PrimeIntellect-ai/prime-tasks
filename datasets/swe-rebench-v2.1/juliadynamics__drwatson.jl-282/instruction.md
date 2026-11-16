Convert strings to symbols on `accesses` option in savename for composite types
I am trying to use the "accesses" keyword in the function savename to choose only a selection of keys for the file name. While I have no issues with the "ignores" keyword, I can't get it to work with "accesses". This is how I call the function:
`name = savename(Params, "eps"; sigdigits = 3, accesses = ["δ", "phi", "v0"])`
which does give me the following error:
`ERROR: MethodError: no method matching getproperty(::MyParams, ::String)`
(where MyParams is the type of Params, a @with_kw struct).

Whereas
`name = savename(Params, "eps"; sigdigits = 3, ignores = ["δ", "phi", "v0"])`
does the right thing.
