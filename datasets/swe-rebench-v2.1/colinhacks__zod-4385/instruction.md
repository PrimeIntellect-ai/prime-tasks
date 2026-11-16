v4: toJSONSchema: `_ref` complicates overrides
core v0.9.0
Let's say there is a schema

```ts
const schema = z.union([
    z.string().date(),
    z.string().datetime(),
    z.string().datetime({ local: true }),
  ]).transform((str) => new Date(str))
    .pipe(z.date())
    .brand("dateIn")
```

When doing `z.toJSONSchema()` with `override` hook, this is what `jsonSchema` argument receives:

```json
{
  "_ref": {
    "_ref": {
      "_ref": {
        "anyOf": [
          {
            "type": "string",
            "format": "date",
            "pattern": "^((\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-((0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])|(0[469]|11)-(0[1-9]|[12]\\d|30)|(02)-(0[1-9]|1\\d|2[0-8])))$"
          },
          {
            "type": "string",
            "format": "date-time",
            "pattern": "^((\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-((0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])|(0[469]|11)-(0[1-9]|[12]\\d|30)|(02)-(0[1-9]|1\\d|2[0-8])))T([01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(\\.\\d+)?(Z)$"
          },
          {
            "type": "string",
            "format": "date-time",
            "pattern": "^((\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-((0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])|(0[469]|11)-(0[1-9]|[12]\\d|30)|(02)-(0[1-9]|1\\d|2[0-8])))T([01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(\\.\\d+)?(Z?)$"
          }
        ]
      }
    }
  }
}
```

so, everything is packed in `_ref` multiple times. The property is optional, so that it may be not be there.
It complicates making overrides.

[HIDDEN]

_For comparison: there was no such issue with core 0.8.1_

### Additional contract requirements

When an override hook is given a JSON Schema fragment, the fragment must not expose internal `_ref` wrappers. Resolving those wrappers must preserve the JSON Schema content they represent.
