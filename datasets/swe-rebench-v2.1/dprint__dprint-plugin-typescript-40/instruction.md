TypeScript: Comma as separator for single-line type literal
**Is your feature request related to a problem? Please describe.**

I want to write this code:

```typescript
type MyObject = { foo: number, bar: string }
```

But dprint-plugin-typescript converts it to semicolons:

```typescript
type MayObject = { foo: number; bar: string }
```

which it is not what I want.

**Describe the solution you'd like**

While I prefer commas as separator, others might prefer semicolons, so I suggest a configuration key should be introduced to specify whether the separator should be commas or semicolons:
* `objectLiteralTypeSeparator: 'comma' | 'semicolon'`
* `singleLineObjectLiteralTypeSeparator: 'comma' | 'semicolon''`
* `multiLineObjectLiteralTypeSeparator: 'comma' | 'semicolon' | 'none'`

**Describe alternatives you've considered**

**Additional context**

I have set `.semi_colons(SemiColons::Asi)` in [my own formatter](https://github.com/KSXGitHub/sane-fmt/blob/0.2.16/src/rules/mod.rs#L14), so I would prefer multi-line object literal type to **not** have separator.

### Additional contract requirements

The configuration keys are `typeLiteral.separatorKind`, `typeLiteral.separatorKind.singleLine`, and `typeLiteral.separatorKind.multiLine`. Each accepts `commas` or `semiColons`. The shared `typeLiteral.separatorKind` setting applies to both single-line and multi-line type literals; the corresponding single-line and multi-line settings override it for their respective layout. When no type-literal separator setting is supplied, the separator is `semiColons`.

When the existing `semiColons` setting is `asi`, a multi-line type literal is emitted with no separator between its members.
