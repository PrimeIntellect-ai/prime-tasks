Error selecting or performing operations on JSON objects containing "sequence" key
node v8.9.3
jsonata v1.5.4
Also able to duplicate on [JSONata Exerciser](http://try.jsonata.org/)

Attempt any selection on an object with a "selection" key.

### The following example works a s expected:
**JSON**
`{
  "foo": {
    "sequence1": 123,
    "bar": "baz"
  }
}`

**JSONata**
`foo.bar`

**Result**
`"baz"`

### When the key is changed to "sequence", it fails:
**JSON**
`{
  "foo": {
    "sequence": 123,
    "bar": "baz"
  }
}`

**JSONata**
`foo.bar`

**Result**
`n.value is not a function`

Repo search revealed 'sequence' being used in https://github.com/jsonata-js/jsonata/blob/7aa65f2295e0605a284e1f1083cf528aceb4ba79/src/jsonata.js#L1557-L1566

### Additional contract requirements

- Performing operations (not only property selection) on a JSON object that contains a `sequence` key must succeed and return the normal result, just as it would for an object without such a key. Applying the `$keys` function to `{ "foo": { "sequence": true, "bar": "baz" } }` must return `["sequence", "bar"]`.
