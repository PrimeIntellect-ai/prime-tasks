showable error on certain objects
On PyCall v1.91.4, Julia 1.5,

```julia
julia> using Conda, PyCall

julia> Conda.add("scikit-learn")   # sorry that it's such a big package

julia> showable(MIME"text/html"(), pyimport("sklearn.linear_model").LogisticRegression)
ERROR: PyError ($(Expr(:escape, :(ccall(#= /Users/cedric/.julia/packages/PyCall/zqDXB/src/pyfncall.jl:43 =# @pysym(:PyObject_Call), PyPtr, (PyPtr, PyPtr, PyPtr), o, pyargsptr, kw))))) <class 'TypeError'>
TypeError("'property' object is not callable")

Stacktrace:
 [1] pyerr_check at /Users/cedric/.julia/packages/PyCall/zqDXB/src/exception.jl:60 [inlined]
 [2] pyerr_check at /Users/cedric/.julia/packages/PyCall/zqDXB/src/exception.jl:64 [inlined]
 [3] _handle_error(::String) at /Users/cedric/.julia/packages/PyCall/zqDXB/src/exception.jl:81
 [4] macro expansion at /Users/cedric/.julia/packages/PyCall/zqDXB/src/exception.jl:95 [inlined]
 [5] #110 at /Users/cedric/.julia/packages/PyCall/zqDXB/src/pyfncall.jl:43 [inlined]
 [6] disable_sigint at ./c.jl:446 [inlined]
 [7] __pycall! at /Users/cedric/.julia/packages/PyCall/zqDXB/src/pyfncall.jl:42 [inlined]
 [8] _pycall!(::PyObject, ::PyObject, ::Tuple{}, ::Int64, ::Ptr{Nothing}) at /Users/cedric/.julia/packages/PyCall/zqDXB/src/pyfncall.jl:29
 [9] _pycall! at /Users/cedric/.julia/packages/PyCall/zqDXB/src/pyfncall.jl:11 [inlined]
 [10] #pycall#115 at /Users/cedric/.julia/packages/PyCall/zqDXB/src/pyfncall.jl:80 [inlined]
 [11] pycall at /Users/cedric/.julia/packages/PyCall/zqDXB/src/pyfncall.jl:80 [inlined]
 [12] showable(::MIME{Symbol("text/html")}, ::PyObject) at /Users/cedric/.julia/packages/PyCall/zqDXB/src/PyCall.jl:894
 [13] top-level scope at REPL[25]:1
```

For context, https://github.com/fonsp/Pluto.jl/issues/412

It might be a scikit-learn issue, but the error message is pretty cryptic.

### Additional contract requirements

- `showable("text/html", o)` must not throw for a Python class object (a type), including when the class defines `_repr_html_` as an ordinary method or as a `property`.
- When a Python class object defines `_repr_html_` as an ordinary method or as a `property`, `showable("text/html", o)` must return `false`.
- A Python instance whose class defines a callable `_repr_html_` must remain showable, i.e. `showable("text/html", o)` returns `true`.
