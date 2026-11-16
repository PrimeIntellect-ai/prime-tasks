Wrong path in ValidationError when validating an object with dotted keys
When validating an object with dotted keys (e.g. `{foo: {'bar.baz': 'zot'}}`) any thrown ValidationErrors will have a `path` that can't be used with things like lodash's `get`, and that will confuse e.g. Formik's error handling.

Example here: https://runkit.com/espenhw/5ce6a57a7e042f001a056407 - I'd like the `path` on the ValidationError to be `a["b.c"]`.
