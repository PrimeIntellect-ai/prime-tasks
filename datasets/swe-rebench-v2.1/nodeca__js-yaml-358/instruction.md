Option to omit space between array elements
We like to encode objects and arrays to query parameters using YAML. The parser is able to parse this correctly:

![image](https://cloud.githubusercontent.com/assets/10532611/25774286/d1d5f0d8-328c-11e7-9e20-164b8bd8a18e.png)

But unfortunately, the dumper always adds unneeded spaces between array elements:

![image](https://cloud.githubusercontent.com/assets/10532611/25774341/53018a8c-328d-11e7-9469-010f01bb52ac.png)

We don't encode `[]` for prettiness and browsers can handle them fine (PHP has used them forever), but spaces of course do need to be encoded, which is not very pretty.

Here are the options I am currently using to output single line YAML:
```js
yaml.safeDump(value, { flowLevel: 0, indent: 0, lineWidth: Infinity, noCompatMode: true, sortKeys: true })
```
It would be great to have an option for omitting these non-required spaces / emitting "minimized" YAML.

### Additional contract requirements

The dumper exposes this opt-in setting as `condenseFlow: true`. When enabled, flow-style arrays omit spaces between successive elements, including arrays nested inside other flow-style arrays.
