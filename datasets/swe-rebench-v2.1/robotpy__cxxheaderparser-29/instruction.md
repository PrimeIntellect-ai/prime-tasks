Parsing error for Standard_Real
When parsing:

```cpp
typedef void   Convert_CosAndSinEvalFunction(Standard_Real,
					     const Standard_Integer,
					     const TColgp_Array1OfPnt2d&,
					     const TColStd_Array1OfReal&,
					     const TColStd_Array1OfInteger*,
					     Standard_Real Result[2]) ;
```

`Standard_Real` is just a type in OpenCASCADE that is a double, I think.

### Additional contract requirements

Parsing a `typedef` that declares a function (for example `typedef void fn(int);`) must succeed and must be reported as a typedef whose aliased type is a function type, instead of raising a parse error.

The aliased function type is the public `FunctionType` dataclass in `cxxheaderparser.types`. It has fields `return_type` (the function's return type), `parameters` (the list of parameters), `vararg` (true when the parameter list ends with `...`, default `False`), `has_trailing_return` (true for a trailing return type such as `auto f() -> T`, default `False`), and `noexcept` (an optional value, default `None`).

The public `Typedef` dataclass in `cxxheaderparser.types` has a `type` field that may hold either a decorated type or a `FunctionType`. For a function typedef, `vararg` is true when its parameter list ends in an ellipsis, and a present `noexcept` specifier (including its value) is preserved in the function type.
