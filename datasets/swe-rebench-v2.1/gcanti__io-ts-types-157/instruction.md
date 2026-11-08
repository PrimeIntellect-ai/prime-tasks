Export `Json` from `JsonFromString`
## 🚀 Feature request

### Current Behavior

The `Json` codec is used in the definition of `JsonFromString`, but it's not exported, and it makes it hard to depend on `JSONFromString` because it's useful to assert for example that "I care that this key exists, but the value of that key is Json too`
https://github.com/gcanti/io-ts-types/blob/master/src/JsonFromString.ts#L27

### Desired Behavior

[HIDDEN]

### Additional contract requirements

- Export a public codec `Json` (type `t.Type<Json>`) from the `JsonFromString` module, re-exported from the package root (`src/index.ts`). It validates JSON values: booleans, numbers, strings, `null`, arrays of JSON values, and objects whose values are JSON values.
- Export a public codec `JsonArray` (type `t.Type<JsonArray>`) from the `JsonFromString` module, re-exported from the package root (`src/index.ts`). It validates JSON arrays: arrays whose elements are themselves valid JSON values. It encodes to a plain JavaScript array and decodes from a plain JavaScript array.
- When `JsonFromString` is composed with `t.type({ a: JsonArray })`, decoding `'{"a":1}'` must produce the validation error message `Invalid value 1 supplied to : pipe(JsonFromString, { a: JsonArray })/a: JsonArray`.
