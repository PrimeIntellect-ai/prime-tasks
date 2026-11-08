PropertyDescriptorResolver: add setValue, similar to getValue
to allow also subexpressions

### Additional contract requirements

- `PropertyDescriptorResolver` (package `org.primefaces.util`) must declare a method `void setValue(Object obj, String expression, Object value)`. The method returns no value.
- `setValue` must throw `javax.faces.FacesException` when an intermediate property in the expression resolves to `null`.
