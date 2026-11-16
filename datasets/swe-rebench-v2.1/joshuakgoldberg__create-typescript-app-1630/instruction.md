🚀 Feature: Add Vitest VS Code Extension to extensions.json?
### Bug Report Checklist

- [X] I have pulled the latest `main` branch of the repository.
- [X] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Overview

I wanted to be able to run tests in VS Code.  For that I found I needed to install the [Vitest VS Code extension](https://marketplace.visualstudio.com/items?itemName=vitest.explorer). I made the following change to my own projects `extensions.json` to recommend this to users:

```diff
[HIDDEN]
```

Would it be worth including that in CTA for users writing tests?

### Additional Info

_No response_

### Additional contract requirements

- For CTA projects whose users write tests, recommend the Vitest VS Code extension (`vitest.explorer`) in the generated VS Code extension recommendations.
