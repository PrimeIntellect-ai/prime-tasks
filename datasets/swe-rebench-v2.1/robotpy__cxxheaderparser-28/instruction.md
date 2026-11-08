Error when parsing 'final' in this line
When parsing:

```cpp
__declspec( dllexport ) Standard_CString CFail (const Standard_Integer num, const Standard_Boolean final = true) const;
```

Get error:
```
cxxheaderparser.errors.CxxParseError: Not able to parse final_error.hxx on line 1 evaluating 'final': unexpected 'final', expected ',' or ')'
```
