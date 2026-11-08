Paths with regex
Hello,

I don't know if it's an Apistos issue or swagger, but when using path containing regex like this one:

```rust
scope("/imgsrv").service(resource("{path:.+}/tile").route(get().to(endpoints::tile::<T>)))
```

It generate this swagger:

![image](https://github.com/user-attachments/assets/24a2fb62-5f9e-4271-b15a-2a150d8526be)

As you can see the curl request is wrong, the `{path:.+}` is not replaced by `test.tif`.
It works well if I use the syntax `{path}`.
One way to fix it may be to sanitize before generating the openapi.json WDYT ?

Thank you

### Additional contract requirements

When a path parameter is declared with a regex pattern, for example `{name:pattern}`:
- the generated OpenAPI path must use the bare parameter name as the placeholder (for example `{name}`), so that a client can substitute a value for it;
- the generated OpenAPI parameter for that placeholder must keep the bare name and must expose the regex pattern as the parameter schema's `pattern` value.
