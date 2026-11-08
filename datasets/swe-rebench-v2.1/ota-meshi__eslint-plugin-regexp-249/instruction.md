`getUsageOfPattern` behaves inconsistently
While writing tests, I found that `getUsageOfPattern` behaves strangely around unknown functions.

The following test cases pass.

```
{
    code: `foo(/[a-zA-Z]\\w*/)`,
    results: [UsageOfPattern.whole],
},
{
    code: `foo({ pattern: /[a-zA-Z]\\w*/ })`,
    results: [UsageOfPattern.unknown],
},
```

Both should have the same result: `unknown`. We do not know how `foo` is implemented. It might use the regex as is or it might return its source.
