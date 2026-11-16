@Deprecated decorator for controller endpoints
It would be nice to have a `@Deprecated` decorator to be able to update your swagger documentation to display endpoints that are not being used/maintained any more.

Right now you can accomplish this updating the `tsoa.json` file with the endpoints you want to deprecate.

### Additional contract requirements

- A `Deprecated()` decorator, defined in `src/decorators/deprecated.ts`, can be applied to a controller endpoint method.
- An endpoint method annotated with `@Deprecated()` is marked as `deprecated` in the generated Swagger 2 and OpenAPI 3 documentation for that operation.
- An endpoint method without `@Deprecated()` is not marked as deprecated by this decorator.
