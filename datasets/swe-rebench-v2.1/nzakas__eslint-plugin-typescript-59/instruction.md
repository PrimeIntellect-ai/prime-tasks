member-delimiter-style single-line override
Today, with `member-delimiter-style: error`:

```ts
export interface Foo { [key: string]: any }
//                                    ^ Expected a semicolon.
```

Suggestion: add an override/option to disable this check for single line type signatures

### Additional contract requirements

- The rule accepts a boolean option named `ignoreSingleLine`. When it is `true`, the delimiter requirement for the last member is not enforced for an interface or type literal whose declaration starts and ends on the same line. When it is `false`, the existing `requireLast` behavior applies to single-line declarations as well.
- `ignoreSingleLine` defaults to `true`, so a single-line interface or type literal does not require a delimiter on its last member unless `ignoreSingleLine` is explicitly set to `false`.
- As with the other options, `ignoreSingleLine` can also be supplied per declaration kind through the `overrides` object, using the `interface` and `typeLiteral` keys.
