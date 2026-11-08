More detailed control over the `prefer-quantifier' rule
Good day,

I have a suggestion regarding the behavior of rule [`prefer-quantifier`](https://ota-meshi.github.io/eslint-plugin-regexp/rules/prefer-quantifier.html).

I definitely agree that `/\d{4}-\d{2}-\d{2}/` is much better than `/\d\d\d\d-\d\d-\d\d`.
However, at the same time, I find the `www` version is clearer and easier to understand than `w{3}`:

```ts
// Removes protocol, www, and trailing slash
url.replaceAll(/^(https?:)?\/\/(www\.)?|\/$/g, '')
url.replaceAll(/^(https?:)?\/\/(w{3}\.)?|\/$/g, '')
```

So I'd like to suggest a few possible options:

1) Add an option to validate only certain character types, such as digits and symbols - for example an open property like `validate: ['digit', 'letter', 'symbol']`. \
If I understand the [implementation](https://github.com/ota-meshi/eslint-plugin-regexp/blob/master/lib/rules/prefer-quantifier.ts) correctly, this would be the easiest option to add and wouldn't introduce any breaking changes.
2) Introduce an explicit whitelist option. \
  I imagine it would be fairly limited in scope, but still useful in specific cases.
3) Increase the validation threshold for letters from 2 to 3. \
  This feels like a weaker solution, but could still help in edge cases like `www`

What do you think?

I can do it myself if this makes sense to you - let me know if this is needed

### Additional contract requirements

- A repeated sequence that would otherwise be reported must not be reported or rewritten when its raw regexp text exactly matches an entry in `allows`. A longer sequence that only begins with an allowed entry is not exempt.
