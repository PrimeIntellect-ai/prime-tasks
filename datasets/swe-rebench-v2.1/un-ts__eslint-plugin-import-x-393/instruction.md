extensions rule autofix requires strange configuration options to work
First of all, thank you @stephenjason89 and @JounQin for getting the extensions autofix contribution merged in #327. I’ve been eager to use Stephen’s PR since I first saw the attempt in import-js/eslint-plugin-import#1749.

I've been finding it difficult to configure the extensions rule autofix to work. I'm suspicious that the behavior I'm seeing is unintentional and might be a bug.

What I've found is that the extensions rule autofix only works when **both** of the following are true:
1. a `fix: true` option is set
2. a `pattern: {}` option is set, even if empty (the contents of the pattern object do not seem to matter)

## Steps to Reproduce

In my testing, these **do not enable** autofix:
```typescript
'import-x/extensions': ['warn', 'never'],
'import-x/extensions': ['warn', 'never', { fix: true }],
'import-x/extensions': ['warn', 'never', { pattern: {} }],
```

But this **does enable** autofix:
```typescript
'import-x/extensions': ['warn', 'never', { fix: true, pattern: {} }],
```

1) is auto-fix meant to be opt-in? I saw [this comment that it was being considered](https://github.com/un-ts/eslint-plugin-import-x/issues/318#issuecomment-2848521188) but it's not documented that way, and none of the other rules have a `fix: boolean` option.
2) I can't imagine requiring a pattern object to enable the flag was intentional.

## Questions
1. Is autofix intended to be opt-in via `fix: true`? I saw [this comment](https://github.com/un-ts/eslint-plugin-import-x/issues/318#issuecomment-2848521188) suggesting it might be, but this [isn’t documented](https://github.com/un-ts/eslint-plugin-import-x/blob/v4.15.2/docs/rules/extensions.md), and no other rules in this project use a fix option. I was only able to discover the `fix: boolean` option by looking through the PR history and source code.
2. Is requiring a pattern object to enable autofix intentional? It seems like an oversight, especially since an empty object works.

Thanks again for all the work on this plugin.

### Additional contract requirements

- For the `extensions` rule, automatic fixing is opt-in: when `fix` is omitted or `false`, the rule provides suggestions instead of applying an automatic fix. When `fix` is `true`, the rule applies automatic fixes.
- Setting `fix: true` must enable automatic fixing without requiring a `pattern` object.
