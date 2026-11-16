Ignore certain "missing message" warnings
In our app we have several translations that are only used on specific locales, but `ember-intl` is constantly warning about them being missing in the other locales, which makes the signal-to-noise ratio quite bad. It would be great if there was an API that would allow us to filter out these messages before they are being passed to the console.

Maybe something like this:

```js
let app = new EmberApp(defaults, {
  'ember-intl': {
    ignoreMissingMessage(message, locale) {
      // your custom logic here
    },
  },
});
```

### Additional contract requirements

Missing-translation handling is configured through the project's `config/ember-intl.js` file, whose exported function returns an options object. The following options are supported:

- `requiresTranslation(key, locale)`: a function called for each translation key that is missing in a locale. Returning `false` excludes that key/locale pair from the reported missing translations. The default requires every key to be present in every locale.
- `throwMissingTranslations`: a boolean. When `true`, the build fails with an `Error` whose message lists every missing translation. When `false` (the default), missing translations are only reported as warnings.

The missing-translation handling supports:

- `findMissingTranslations(translations)`: returns an array of `[key, locales]` tuples, where `key` is a missing translation key and `locales` is the array of locales in which it is missing, after applying `requiresTranslation`.
- `handleMissingTranslations(missingTranslations)`: accepts the array returned by `findMissingTranslations`. When `verbose` is `true` and `throwMissingTranslations` is `false`, it logs each missing-translation message through the `log` option. When `throwMissingTranslations` is `true`, it throws an `Error` whose message starts with `Missing translations:` and then has one line per missing key, in input order, formatted as `- "key" was not found in "locale"` (listing multiple locales in their input order, separated by `, `). The message has no trailing newline.
