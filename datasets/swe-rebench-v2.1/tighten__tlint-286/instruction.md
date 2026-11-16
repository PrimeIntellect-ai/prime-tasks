NoRequestAll incorrectly identifies $request->user()
I have recently created a new Laravel 9.6.0 project, installed Jetstream Inertia, then added Tighten/TLint. I created a custom Preset to include more linters including Linters\NoRequestAll.

This linter now identifies the following code as violating NoRequestAll:

```
Route::middleware('auth:sanctum')->get('/user', function (Request $request) {
    return $request->user();
});
```
