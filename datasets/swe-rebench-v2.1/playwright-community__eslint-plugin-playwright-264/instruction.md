no-useless-not is unaware of `enabled`/`visible` parameter
this reports "Unexpected usage of not.toBeVisible(). Use toBeHidden() instead", but using toBeHidden can't be used with a parameter.
```js
let visible = false;
// reports no-useless-not
await expect(page.locator('#selector')).not.toBeVisible({ visible });
```
same for `toBeEnabled`.

The lint was added in https://github.com/playwright-community/eslint-plugin-playwright/pull/81. Shortly thereafter, playwright 1.26 was released which added these parameters.
