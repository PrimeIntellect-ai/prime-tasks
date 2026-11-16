Feature Request - Boolean type cast
#### Context

* *node version*: v4.5
* *joi version*: 9.0.4
* *environment* (node, browser): node
* *used with* (hapi, standalone, ...): standalone
* *any other relevant information*:

#### Feature
Is it possible to add "Y" and "N" in boolean type cast? MLS & bunch of state tax record data often do "Y"

### Additional contract requirements

- The boolean type no longer performs implicit string or number coercion. A plain `Joi.boolean()` schema accepts only actual boolean values; the previous casting of `'true'`, `'false'`, `'yes'`, `'no'`, `'on'`, `'off'`, `'1'`, `'0'`, `1`, and `0` is removed.
- Support for additional values such as `"Y"` and `"N"` is provided through the `truthy()` and `falsy()` methods described in the interface, not through default casting.
- `truthy()` and `falsy()` each return a new cloned schema and leave the source schema unchanged.
- Passing `undefined` to `truthy()` or `falsy()` throws.
