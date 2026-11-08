Error for __declspec
When parsing:

```cpp
class CDM_MetaData : public Standard_Transient
{

public:

friend class CDM_Reference;
friend
  //! associates database  information to  a document which
  //! has been stored.  The name of the  document is now the
  //! name which has beenused to store the data.
  __declspec( dllexport ) void CDM_Document::SetMetaData (const opencascade::handle<CDM_MetaData>& aMetaData);
friend
  __declspec( dllexport ) void CDM_Application::SetDocumentVersion (const opencascade::handle<CDM_Document>& aDocument, const opencascade::handle<CDM_MetaData>& aMetaData) const;

};
```

I am parsing the OpenCASCADE headers, by the way. That is where all the errors are coming from.

### Additional contract requirements

- The parser exposes parsed declarations through the public classes `Method` and `FriendDecl` in the module `cxxheaderparser.types`.
- `Method` is constructed as `Method(return_type, name, parameters, static=False, access="public", **kwargs)`: `return_type` is the return type, `name` is the (possibly qualified) name, `parameters` is the list of parameters, `static` marks a static method, and `access` is the access specifier.
- `FriendDecl` is constructed as `FriendDecl(fn)`, wrapping the function object for a friend function declaration.
- A class-scope friend function declaration such as `friend __declspec(dllexport) void my_friend();` is represented as `FriendDecl(fn=Method(...))` whose return type is `void`, whose name is `my_friend`, which has no parameters, and whose access is `"public"`.
- Attributes such as `__declspec(...)` are accepted when parsing declarations, including a static member function such as `static __declspec(dllexport) void static_declspec();`, which is represented as a `Method` with `static=True` and `access="public"`.
- Friend function declarations that use a qualified name, parameters, and a trailing `const` are parsed without error, preserving the qualified name, the parameters, and the `const` qualifier.
