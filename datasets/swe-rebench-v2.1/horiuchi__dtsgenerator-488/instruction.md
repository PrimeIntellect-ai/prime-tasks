improvement: support freeform objects w/ index signature instead of unknown keyword
Hi !

This change improves the output of objects without properties by generating an object type with an index signature: `{ [key: string]: any }`.

Now that i think of it, perhaps it'd be better to have `{ [key: string]: unknown }` instead?

Thanks

PR: #488

### Additional contract requirements

For an object schema with no properties, generated declarations must represent a freeform object with a string index signature whose value type is `any`, rather than `unknown`.
