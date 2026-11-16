Calling custom() before save() should trigger a console error
Building the resource URL for the request is done for you by calling `resource()` of the model you are creating the request with.
This can be overridden with `custom()` for GET requests and `for()` for POST/PUT/PATCH/DELETE requests.

Users of the library often don't realize that `custom()` was made to query records on, for example, `/posts/latest` which is a conceivable resource URL. It is not RESTful to save/delete records on endpoints such as this.

People should be made aware that `for()` needs to be used for saving/deleting records.

The library should output a console error if `save()` is called after `custom()`.

### Additional contract requirements

Calling `save()`, `delete()`, `attach(params)` or `sync(params)` on a model whose custom resource was set with `custom()` must throw an `Error` with these exact messages:

- `save()`: `The save() method cannot be used in conjunction with the custom() method. Use for() instead.`
- `delete()`: `The delete() method cannot be used in conjunction with the custom() method. Use for() instead.`
- `attach()`: `The attach() method cannot be used in conjunction with the custom() method. Use for() instead.`
- `sync()`: `The sync() method cannot be used in conjunction with the custom() method. Use for() instead.`
