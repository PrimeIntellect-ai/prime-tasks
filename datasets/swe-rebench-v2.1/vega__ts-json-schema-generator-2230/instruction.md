Incorrect `additionalProperties` schema generated for `Pick<T, AliasLiteralUnion>`
When using `Pick<T, AliasLiteralUnion>` - where the union is composed of type aliases to literal strings - the generator incorrectly emits an `additionalProperties` sub-schema (e.g., `{ "type": ... }`) instead of respecting the `--additional-properties` setting.

## Reproduction:

```ts
interface SomeInterface {
  foo: string;
  bar: number;
}

type AliasFoo = "foo";
type AliasBar = "bar";

export type PickUnionOfLiteralsAliases = Pick<SomeInterface, AliasFoo | AliasBar>;
```

## Expected Output ✅
```json
"PickUnionOfLiteralsAliases": {
  "type": "object",
  "properties": {
    "foo": { "type": "string" },
    "bar": { "type": "number" }
  },
  "required": ["foo", "bar"],
  "additionalProperties": false
}
```
This is the correct output, and it's exactly what the generator produces when the union is written inline:
```ts
export type PickWithLiteralUnion = Pick<SomeInterface, "foo" | "bar">;
```

## Current Output ❌
However, when using aliases, we get:
```json
"PickUnionOfLiteralsAliases": {
  "type": "object",
  "properties": {
    "foo": { "type": "string" },
    "bar": { "type": "number" }
  },
  "required": ["foo", "bar"],
  "additionalProperties": { "type": "string" }  // ← unexpected
}
```

## Root cause
[HIDDEN]

As a result, keys like:
```ts
type AliasFoo = "foo";
```
…are not recognized as literals, and the generator assumes an open-ended keyset.

[HIDDEN]
