Error: Unknown type: TypeOperator
I'm having an issue when trying to define a type with keys of an enum.

## Sorting

* **I'm submitting a ...**
  - [x] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior

```ts
enum Enum {
  OK,
  KO
}
export interface SerializedDatasource {
  enumKeys: keyof typeof Enum // which produces 'OK' | 'KO'
}
```

```yaml
enumKeys:
  type: string
  enum:
    - OK
    - KO
```

## Current Behavior

```
There was a problem resolving type of 'SerializedDatasource'.
Generate swagger error.
 Error: Unknown type: TypeOperator
At: src/controllers/test.ts:11:11.
This was caused by 'enumKeys: keyof typeof Enum'
    at new GenerateMetadataError (/private/tmp/tsoa-bug/packages/api/node_modules/tsoa/dist/metadataGeneration/exceptions.js:21:28)
    at TypeResolver.resolve (/private/tmp/tsoa-bug/packages/api/node_modules/tsoa/dist/metadataGeneration/typeResolver.js:243:19)
    at TypeResolver.propertyFromSignature (/private/tmp/tsoa-bug/packages/api/node_modules/tsoa/dist/metadataGeneration/typeResolver.js:645:119)
    at /private/tmp/tsoa-bug/packages/api/node_modules/tsoa/dist/metadataGeneration/typeResolver.js:612:161
    at Array.map (<anonymous>)
```

## Context (Environment)
Version of the library: "3.0.4"
Version of NodeJS: v12.14.1
* Confirm you were using yarn not npm: [x]
