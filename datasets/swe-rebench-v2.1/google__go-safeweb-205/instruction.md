Consider removing WriteTemplate and WriteJSON, implement helpers to just rely on Write
### Rationale

Currently we have a quite low-level API (`Write(Response)`) and two very high-level one, which are tailored to a specific function.

My proposal is to just stick to the general purpose API (Write) which is the one responsible for the wiring with the Dispatcher.

This will keep the interface for Dispatcher and ResponseWriter simpler, and will make it clear that the responsibility for wrapping and handling different types is on the Dispatcher implementers.

This will also remove the duplicated code that we have that asks for content-type in every call to WriteTemplate, WriteJSON etc.

### Template

The specific type we require is a `Template` interface but we actually ask more of it: for example when we will need to nonce-inject we will need Clone and Funcs methods, and we cannot express the Clonable interface, so we will be asking users to implement something, but will **implicitly ask for more**.

Moreover this API does not work if we have to call ExecuteTemplate instead, which will require an additional string parameter.

To then render templates we would offer helpers that would look like these: `w.Write(mytpl.WithData(data))` `w.Write(mytpl.NamedWithData("foo", data))`. If we don't want to change the packages that export the templates we can also put those helpers and wrappers in safehttp directly (which we are already doing anyways, even if in another form). With the extra added benefit that the signature will match the exact types we expect.

### JSON

Currently WriteJSON just wraps things in a JsonResponse. We could just create an helper for that and pass JSONResponse to Write. Example usage would look like `w.Write(safehttp.JsonResponse{data})` instead of `w.WriteJSON(data)` so it will be slightly more verbose but I think the overall API will benefit from the simplification.

### An optional extra step
We could even make the so-created `Response` implementations have an (unexported) method that takes care of properly setting the content-type and one for serializing the body, which would allow us to actually limit the `safehttp.Response` implementers to be checked at compile-time.

At that point the dispatcher responsibility would just be to check that something extraneous to safehttp is an acceptably safe response when put in a generic wrapper.

Overall we would reduce the typeswitching a lot and make the API cleaner.

### Additional contract requirements

- The `safehttp.Dispatcher` interface exposes a single writing method, `Write(rw http.ResponseWriter, resp Response) error`. The former `Dispatcher.WriteJSON` and `Dispatcher.ExecuteTemplate` methods are removed.
- The `safehttp.ResponseWriter` type no longer exposes `WriteJSON` or `WriteTemplate`; every response is written through `ResponseWriter.Write(resp Response) Result`.
- Add a package-level function `WriteJSON(w *ResponseWriter, data interface{}) Result` in package `safehttp` that wraps `data` in a `JSONResponse` and forwards it to `w.Write`.
- Add a package-level function `ExecuteTemplate(w *ResponseWriter, t Template, data interface{}) Result` in package `safehttp` that wraps `t` and `data` in a `TemplateResponse` with no function map and forwards it to `w.Write`.
- Add a package-level function `ExecuteTemplateWithFuncs(w *ResponseWriter, t Template, data interface{}, fm map[string]interface{}) Result` in package `safehttp` that wraps `t`, `data` and `fm` in a `TemplateResponse` and forwards it to `w.Write`.
- The exported `TemplateResponse` struct in package `safehttp` has the fields, in order: `Template Template`, `Data interface{}`, `FuncMap map[string]interface{}`.
- `DefaultDispatcher.Write` writes `safehtml.HTML`, `JSONResponse` and `TemplateResponse` values to the underlying `http.ResponseWriter`, and returns a non-nil error for any other response type.
