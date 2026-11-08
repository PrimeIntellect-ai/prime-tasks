condenseFlow results in invalid object keys
```js
jsYaml.safeDump({key: 'value'}, {
    flowLevel: 0,
    indent: 0,
    lineWidth: Infinity,
    noCompatMode: true,
    sortKeys: true,
    noRefs: true,
    condenseFlow: true
})
```
results in actual YAML:
```yaml
{key:value}
```
but parsing that with `safeLoad()` results in
```js
{ 'key:value': null }
```

Expected YAML:
```yaml
{"key":value}
# or
{key: value}
```
which results in
```js
{ key: 'value' }
```

it would be best if the quoting of the key would be controlled by a `quoteKeys` setting.

cc @eseliger

### Additional contract requirements

- For `{ a: { b: 'c' } }` with `flowLevel: 0`, `indent: 0`, and `condenseFlow: true`, `dump()` must return `'{"a":{"b":c}}\n'`.
- For `[ 'a', 'b' ]` with `flowLevel: 0`, `indent: 0`, and `condenseFlow: true`, `dump()` must return `'[a,b]\n'`.
