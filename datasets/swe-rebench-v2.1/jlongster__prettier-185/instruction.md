Incorrectly removing parenthesis around await expression
Before:

```js
    assert.equal(
      (await driver.browser.activeWindow.navigator.getUrl()).substr(-7),
      '?q=1357',
    );
```

After:

```js
assert.equal(await driver.browser.activeWindow.navigator.getUrl().substr(-7), '?q=1357');
```

Before this change, the expression being awaited was:

```js
driver.browser.activeWindow.navigator.getUrl()
```

but after it is:

```js
driver.browser.activeWindow.navigator.getUrl().substr(-7)
```
