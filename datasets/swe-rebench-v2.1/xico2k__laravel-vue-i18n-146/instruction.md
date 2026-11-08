Translation set to null if key doesn't exist
In our project, we don't have translations for simple strings in `en_US.json`, only in any other language. So, when we use wTrans within our code, the value is initially set to the key, but then once `loadLanguageAsync` finishes it is set to null by [this piece of code](https://github.com/xiCO2k/laravel-vue-i18n/blob/main/src/index.ts#L357) because the translation key doesn't exist.

Here is a test to reproduce our issue.
```js
it('checks if watching translation works if key does not exist', async () => {
    await global.mountPlugin('<div />');

    const translated = wTrans('Welcome to the Vue!');

    expect(translated.value)
        .toBe('Welcome to the Vue!');

    await loadLanguageAsync('en');

    // Fails because translated.value now equals to null
    expect(translated.value)
        .toBe('Welcome to the Vue!');
})
```

One possible solution I found is [HIDDEN], but I have no idea if it can result in some performance issues, so it would be wise to check first. Hopefully, you will find a solution.

```js
wTrans(key: string, replacements: ReplacementsInterface = {}): ComputedRef<string> {
  [HIDDEN]

  return computed(() => this.makeReplacements(this.activeMessages[key], replacements))
}
```

### Additional contract requirements

- If a translation key is absent after asynchronous language loading, `wTrans` must continue to return the key rather than `null`.
