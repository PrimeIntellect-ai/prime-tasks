Allow  $request->validate()

### Additional contract requirements

The linter must not report `$request->validate()` calls made on an injected request instance. This includes calls whose returned validated data is used and calls wrapped in exception handling for a failed validation.
