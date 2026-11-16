UUID v7 and v8 do not pass validation
Despite being perfectly valid versions, [UUIDv7](https://datatracker.ietf.org/doc/html/rfc9562#name-uuid-version-7) and [UUIDv8](https://datatracker.ietf.org/doc/html/rfc9562#name-uuid-version-8) are flagged as invalid by the `uuid` type validator.

The UUID validator and types needs to be updated to properly take those two versions into account.

Actual behavior:
```js
const checkUUID = v.compile({ $$root: true, type: "uuid" });
checkUUID("01965dfe-77ac-78e2-9f69-51e5ce8bd080") // not true
```

### Additional contract requirements

- The `uuid` rule accepts an optional `version` option whose value is one of `0`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`. When a version is specified, a UUID whose version digit does not match is rejected with an error of type `uuidVersion`; when the option is omitted, any supported UUID version, including 7 and 8, is accepted.
- The package exports a TypeScript type `RuleUUID` from its root module. Its `version` property accepts the values `0` through `8`.
