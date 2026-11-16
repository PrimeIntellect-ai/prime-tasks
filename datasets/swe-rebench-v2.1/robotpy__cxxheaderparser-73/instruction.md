Error parsing '<'
In this code:

```cpp
template<>
template<>
inline Standard_CString StdObjMgt_Attribute<TDF_TagSource>::Simple<Standard_Integer>::PName() const
  { return "PDF_TagSource"; }
```

this looks weird to me, but i'm just taking this from snippets of source code from an upstream library
