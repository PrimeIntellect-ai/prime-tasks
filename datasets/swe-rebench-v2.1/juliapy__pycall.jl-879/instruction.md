propertynames fails for "optional" property decorators
When a Python class has an optional property decorator (i.e. only works when some optional dependency is available), then `propertynames` fails. Here's a minimal example:

```julia
julia> using PyCall
[ Info: Precompiling PyCall [438e738f-606a-5dbb-bf0a-cddfbfd45ab0]

julia> py"""
       class MyClass:
           _myprop = None

           @property
           def myprop(self):
               if self._myprop is None:
                   raise(Exception("myprop is not defined"))
               return self._myprop
       """

julia> o = py"MyClass()"
PyObject <__main__.MyClass object at 0x7fb2d9011fa0>

julia> propertynames(o)
ERROR: PyError ($(Expr(:escape, :(ccall(#= /Users/saxen/.julia/packages/PyCall/BcTLp/src/pyfncall.jl:43 =# @pysym(:PyObject_Call), PyPtr, (PyPtr, PyPtr, PyPtr), o, pyargsptr, kw))))) <class 'Exception'>
Exception('myprop is not defined')
  File "/Users/saxen/.julia/conda/3/lib/python3.8/inspect.py", line 350, in getmembers
    value = getattr(object, key)
  File "/Users/saxen/.julia/packages/PyCall/BcTLp/src/pyeval.jl", line 7, in myprop
    pynamespace(m::Module) =

Stacktrace:
 [1] pyerr_check at /Users/saxen/.julia/packages/PyCall/BcTLp/src/exception.jl:62 [inlined]
 [2] pyerr_check at /Users/saxen/.julia/packages/PyCall/BcTLp/src/exception.jl:66 [inlined]
 [3] _handle_error(::String) at /Users/saxen/.julia/packages/PyCall/BcTLp/src/exception.jl:83
 [4] macro expansion at /Users/saxen/.julia/packages/PyCall/BcTLp/src/exception.jl:97 [inlined]
 [5] #110 at /Users/saxen/.julia/packages/PyCall/BcTLp/src/pyfncall.jl:43 [inlined]
 [6] disable_sigint at ./c.jl:446 [inlined]
 [7] __pycall! at /Users/saxen/.julia/packages/PyCall/BcTLp/src/pyfncall.jl:42 [inlined]
 [8] _pycall!(::PyObject, ::PyObject, ::Tuple{PyObject}, ::Int64, ::Ptr{Nothing}) at /Users/saxen/.julia/packages/PyCall/BcTLp/src/pyfncall.jl:29
 [9] _pycall! at /Users/saxen/.julia/packages/PyCall/BcTLp/src/pyfncall.jl:11 [inlined]
 [10] #pycall#115 at /Users/saxen/.julia/packages/PyCall/BcTLp/src/pyfncall.jl:80 [inlined]
 [11] pycall at /Users/saxen/.julia/packages/PyCall/BcTLp/src/pyfncall.jl:80 [inlined]
 [12] propertynames(::PyObject) at /Users/saxen/.julia/packages/PyCall/BcTLp/src/PyCall.jl:319
 [13] top-level scope at REPL[7]:1

julia> o._myprop = 1
1

julia> propertynames(o)
28-element Array{Symbol,1}:
 :__class__
 :__delattr__
 :__dict__
 :__dir__
 :__doc__
 :__eq__
 :__format__
 :__ge__
 :__getattribute__
 :__gt__
 :__hash__
 :__init__
 :__init_subclass__
 :__le__
 :__lt__
 :__module__
 :__ne__
 :__new__
 :__reduce__
 :__reduce_ex__
 :__repr__
 :__setattr__
 :__sizeof__
 :__str__
 :__subclasshook__
 :__weakref__
 :_myprop
 :myprop
```

[HIDDEN]

```julia
julia> py"dir(MyClass())"
28-element Array{String,1}:
 "__class__"
 "__delattr__"
 "__dict__"
 "__dir__"
 "__doc__"
 "__eq__"
 "__format__"
 "__ge__"
 "__getattribute__"
 "__gt__"
 "__hash__"
 "__init__"
 "__init_subclass__"
 "__le__"
 "__lt__"
 "__module__"
 "__ne__"
 "__new__"
 "__reduce__"
 "__reduce_ex__"
 "__repr__"
 "__setattr__"
 "__sizeof__"
 "__str__"
 "__subclasshook__"
 "__weakref__"
 "_myprop"
 "myprop"
```
