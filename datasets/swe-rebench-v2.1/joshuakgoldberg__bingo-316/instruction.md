🐛 Bug: Stratum Addon merger error detection misses root-level arrays
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/bingo/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

`mergeAddonsIfUpdate` is meant to return an error if an array is requested to be merged with a non-array

### Actual

In trying to get this `create-typescript-app.config.js` with `create-typescript-app@2.14.0`:

```js
import {
  blockCTATransitions,
  blockESLint,
  createConfig,
} from "../create-typescript-app/lib/index.js";

export default createConfig({
  refinements: {
    addons: [
      blockESLint({
        rules: { "n/no-unpublished-import": "off" },
      }),
    ],
    blocks: {
      add: [blockCTATransitions],
    },
  },
});
```

I see that `rules` is being merged as:

```js
{
  "0": ...,
  "n/no-unpublished-import": "off",
}
```

### Additional Info

💝
