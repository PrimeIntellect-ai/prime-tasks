Cannot get source for generated functions
The following fails (tested on 1.6.5 and on nightly):

```julia
module MWE

using DocStringExtensions

@template METHODS =
    """
    $(DOCSTRING)
    $(TYPEDSIGNATURES)
    """

"Docstring."
@generated f(x) = :(2 * $(length(x)))

end
```

```julia
help?> MWE.f

ERROR: Method is @generated; try `code_lowered` instead.
Stacktrace:
  [1] error(s::String)
    @ Base ./error.jl:33
  [2] uncompressed_ir(m::Method)
    @ Base ./reflection.jl:988
  [3] get_method_source
    @ ~/.julia/packages/DocStringExtensions/iscC8/src/utilities.jl:354 [inlined]
  [4] arguments(m::Method)
    @ DocStringExtensions ~/.julia/packages/DocStringExtensions/iscC8/src/utilities.jl:434
  [5] format(#unused#::DocStringExtensions.TypedMethodSignatures, buf::IOBuffer, doc::Base.Docs.DocStr)
    @ DocStringExtensions ~/.julia/packages/DocStringExtensions/iscC8/src/abbreviations.jl:381
  [6] formatdoc(buf::IOBuffer, doc::Base.Docs.DocStr, part::DocStringExtensions.TypedMethodSignatures)
    @ DocStringExtensions ~/.julia/packages/DocStringExtensions/iscC8/src/abbreviations.jl:25
  [7] format(abbr::DocStringExtensions.Template{:after}, buf::IOBuffer, doc::Base.Docs.DocStr)
    @ DocStringExtensions ~/.julia/packages/DocStringExtensions/iscC8/src/abbreviations.jl:647
  [8] formatdoc(buf::IOBuffer, doc::Base.Docs.DocStr, part::DocStringExtensions.Template{:after})
    @ DocStringExtensions ~/.julia/packages/DocStringExtensions/iscC8/src/abbreviations.jl:25
  [9] formatdoc(d::Base.Docs.DocStr)
    @ REPL /buildworker/worker/package_linux64/build/usr/share/julia/stdlib/v1.6/REPL/src/docview.jl:88
 [10] parsedoc(d::Base.Docs.DocStr)
    @ REPL /buildworker/worker/package_linux64/build/usr/share/julia/stdlib/v1.6/REPL/src/docview.jl:96
 [11] map!(f::typeof(Base.Docs.parsedoc), dest::Vector{Any}, A::Vector{Base.Docs.DocStr})
    @ Base ./abstractarray.jl:2287
 [12] mapany
    @ ./abstractarray.jl:2296 [inlined]
 [13] doc(binding::Base.Docs.Binding, sig::Type)
    @ REPL /buildworker/worker/package_linux64/build/usr/share/julia/stdlib/v1.6/REPL/src/docview.jl:192
 [14] doc(binding::Base.Docs.Binding)
    @ REPL /buildworker/worker/package_linux64/build/usr/share/julia/stdlib/v1.6/REPL/src/docview.jl:160
 [15] top-level scope
    @ /buildworker/worker/package_linux64/build/usr/share/julia/stdlib/v1.6/REPL/src/docview.jl:476
```

[HIDDEN]

### Additional contract requirements

- Documentation signature formatting for a generated method must succeed and reflect its declared argument signature, including argument names and declared types.
