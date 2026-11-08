[K2] Missing param tag for type parameter on implicit primary constructor
```
/** @param T a type */
class Foo<T>
```

With K1, the `documentation` on the `DFunction` for the implicit primary constructor of `Foo` is
`DocumentationNode(children=[Param(root=CustomDocTag(children=[P(children=[Text(body=a type, children=[], params={})], params={})], params={}, name=MARKDOWN_FILE), name=T)])`.

With K2, the `documentation` for the constructor `DFunction` is empty.

Possibly related to #3348?
