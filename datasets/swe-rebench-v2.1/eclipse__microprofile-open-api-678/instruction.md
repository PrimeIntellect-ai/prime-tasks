Add methods to access a single extension to `Extensible`
Retrieving an extension via `Extensible` currently requires the use of `getExtensions` to acquire the entire extension map, which can then be used to pick the single entry. We should add `getExtension(String)` and `hasExtension(String)` methods to allow implementations to provide more efficient ways to access single entries.

Default methods can be provided to make more efficient implementations optional:

```java
default boolean hasExtension(String name) {
    [HIDDEN]
}

default Object getExtension(String name) {
    [HIDDEN]
}
```

### Additional contract requirements

- `hasExtension(String)` must return true when the named extension is present, and false when it is absent or the extensions map is null.
- `getExtension(String)` must return the value for the named extension, or null when the extension is absent or the extensions map is null.
