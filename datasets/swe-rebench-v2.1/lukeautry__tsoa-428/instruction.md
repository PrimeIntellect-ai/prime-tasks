Method return type problem when dealing with arrays
If you define a request handler and want to return an array of some type you will face a type naming issue in the OpenAPI specification when writing
```
public testGet(): T[] {}
```
instead of
```
public testGet(): Array<T> {}
```


If you then try to generate an API client using the Swagger codegen executable you will face the issue of return types like this (Dart):
```
static List<T[]> listFromJson(List<dynamic> json) {}
```
Expected behavior:
```
static List<T> listFromJson(List<dynamic> json) {}
```

### Additional contract requirements

- When a method returns an array written as `T[]`, the generated API description must describe an array whose element type is `T`, so that a client generated from it receives a list of `T` rather than a list of `T[]`.
- The same holds for arrays written as `T[]` that are used as type arguments of a generic type (for example `GenericRequest<T[]>` or `GenericModel<T[]>`): the generated array's element type is `T`.
- No type name generated for an array written as `T[]` may contain `[` or `]`.
