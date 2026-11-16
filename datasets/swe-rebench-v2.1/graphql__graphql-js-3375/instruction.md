printSchema: creates invalid block strings for descriptions
Not every string can be represented as block string but currently `printSchema` uses block strings for all descriptions.
Example:
```js
const { buildSchema, parse, printSchema } = require('./dist');
const schema = buildSchema('" " scalar Foo');
const printedSDL = printSchema(schema);
console.log(printedSDL);
// """ """
// scalar Foo

console.log(printSchema(buildSchema(printedSDL)));
// """"""
// scalar Foo
```

We should add a new utility function (in `blockString.js`) that checks if the string can be represented as a block string and use it inside `printSchema.js`.
Based on our previous experience with block strings it would be hard to cover all edge cases so I strongly suggest writing fuzzing test for this new function, similar to this one:
https://github.com/graphql/graphql-js/blob/47ac276f21598db5690f287f2f0ea41bbdeef4ca/src/language/__tests__/blockString-fuzz.js#L24

### Additional contract requirements

- Add a public function `isPrintableAsBlockString(value: string): boolean` in `src/language/blockString.ts` that returns whether the value can be safely represented as a GraphQL block string.
- Add a public function `dedentBlockStringLines(lines: ReadonlyArray<string>): Array<string>` in `src/language/blockString.ts` that removes common indentation except from the first line and strips leading and trailing blank lines.
- `printBlockString(value: string, options?: { minimize?: boolean }): string` in `src/language/blockString.ts` returns a block-string literal for the value. When `minimize` is `true` it prefers the most compact representation.
