Use a safe stringify helper in place of JSON.stringify
Log lines that stringify objects with cyclical references throw. These references can come from external objects like the media element that have addition properties on them. Example #7008.

### Additional contract requirements

- Add a public function `stringify<T>(object: T, replacer?: (this: any, key: string, value: any) => any): string` in module `src/utils/safe-json-stringify`.
- The `object` argument may be any JSON-serializable value, including primitives, arrays and objects.
- Circular references are omitted from the output (replaced by `undefined`) and no error is thrown when the input contains cycles.
- When a `replacer` is supplied, its transformed values are included in the output, including when a transformation removes or introduces circular references.
- Object serialization performed for log messages must tolerate externally introduced circular references without making log creation throw.
