Return JSON format when referenced value is not a simple type
As @adnanh wrote in https://github.com/adnanh/webhook/pull/446#issuecomment-667168746:

> when fetching the referenced parameter which turns out to be an object or an array, return a JSON string representation of it. At the moment it will invoke ToString() on the object which usually ends up with something like `map[foo: bar]` for payload such as `{"foo": "bar"}`

### Additional contract requirements

- The JSON representation must be compact, with no insignificant whitespace (for example, `{"z":1}` and `["y","z"]`).
