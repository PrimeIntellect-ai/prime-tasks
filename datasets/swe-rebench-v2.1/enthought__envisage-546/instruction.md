`bind_extension_point` prevents object garbage collection
`bind_extension_point` stores a reference to the binding and prevents collection of the object, and it does not offer any way to `unbind` either.

`ExtensionPointBinding` objects are stored in a `WeakKeyDictionary` mapping `object` weakref to the `ExtensionPointBinding` instance, but the binding itself stores a strong reference to the `object` and hence prevents its garbage collection.

### Additional contract requirements

- Provide the public operation `unbind_extension_point(obj, trait_name, extension_point_id, extension_registry)` to remove the matching extension-point binding.
- After unbinding, subsequent contributions to that extension point must no longer affect the target trait, and the binding must no longer keep the target object from being garbage-collected.
