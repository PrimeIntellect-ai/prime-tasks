PropertyDescriptorResolver: add setValue, similar to getValue
to allow also subexpressions

### Additional contract requirements

Add a public method `void setValue(Object obj, String expression, Object value)` to the public interface `org.primefaces.util.PropertyDescriptorResolver`. It writes `value` to the property named by `expression` on `obj`, where `expression` is a dot-separated property path (for example `address.street`). Simple and nested writable properties must be supported, and each intermediate segment must resolve to a non-null object.

`setValue` throws `javax.faces.FacesException` when the final property is read-only, when an intermediate property resolves to null, or when a reflective error occurs while resolving or writing the property (including when the property's accessor throws).
