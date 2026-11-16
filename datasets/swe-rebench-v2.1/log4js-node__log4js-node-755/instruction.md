DeprecationWarning: Custom inspection function on Objects via .inspect() is deprecated
When logging an `Error` object, the following prints to the console:
```
(node:93348) [DEP0079] DeprecationWarning: Custom inspection function on Objects via .inspect() is deprecated
```

See deprecation notice for node v10:
[[DEP0079] DeprecationWarning: Custom inspection function on Objects via .inspect() is deprecated](https://nodejs.org/api/deprecations.html#deprecations_dep0079_custom_inspection_function_on_objects_via_inspect)

### Additional contract requirements

- Logging an `Error` must not emit the deprecated custom-inspection warning (DEP0079).
- When an `Error` object is logged, the layout renders the error's own representation: its stack trace (the value of the error's `stack` property), followed by any additional own enumerable properties that have been added to the error object.
- For a `basicLayout` event whose data is `['this is a test', error]`, retain the string before the error. The first output line contains the standard `[timestamp] [level] category - ` prefix, followed by `this is a test`, a space, and the first line of the error's stack trace (`Error: <message>`). Each subsequent output line corresponds to the next line of the stack trace.
