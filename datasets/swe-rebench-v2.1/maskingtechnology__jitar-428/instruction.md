UnexpectedKeyword [Error]: Unexpected keyword 'as' at position 8482
When building a full stack application using Vite, the front end is minimized using rollup. The minified files include the react library, and randomly named functions. The react items that are added contain the keyword `as` in an error string.

```ts
Error("Objects are not valid as a React child (found: " ...
```

Or as the name of a function

```ts
function as(e,n,t){var r,l={},i=null,o=null;t!==void 0&&(i=""+t),n.key!==void 0&&(i=""+n.key),n.ref!==void 0&&(o=n.ref);
```

The parser seems to trip over these values, and throws an error. These generated files prevent jitar to start, and the influence we have on the generated values is minimal.

To get Jitar started, it helps to replace the `as` values in the file to `als`. Then Jitar will simply start and function normally.

The generated file is attached to this ticket below.

[assets.zip](https://github.com/MaskingTechnology/jitar/files/13813282/assets.zip)

### Additional contract requirements

The parser must accept `as` as a non-reserved keyword wherever an identifier is expected, instead of throwing an `UnexpectedKeyword` error. In particular:

- `const as = 'value';` parses to a declaration named `as` whose value is the expression `'value'`.
- `const alias = as;` parses to a declaration named `alias` whose value is the expression `as`.
- `function as() {}` parses to a function named `as` that is not async, has no parameters, and has body `{ }`.
