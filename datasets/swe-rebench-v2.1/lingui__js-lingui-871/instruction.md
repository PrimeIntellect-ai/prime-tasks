Compile not working with unstranslated strings
I am having an issue compiling messages, when some strings are untranslated. I am not able report one specific bug, as I am unsure what is intended behaviour and what is not. So to explain the issue I will walk through what I have tried, and hopefully it will make sense what the issue it.

So I created a fresh create-react-app following the instructions in the documentation. I then changed the locales, shown in this configuration.
```JSON
{
  "locales": [
    "en-US",
    "en-CA",
    "fr-CA"
  ],
  "sourceLocale": "en-US",
  "catalogs": [
    {
      "path": "src/locales/{locale}/messages",
      "include": [
        "src"
      ]
    }
  ],
  "format": "po"
}
```
I then ran `lingui extract` and `lingui compile` and that is when the first error appeared:
```
/.../node_modules/@lingui/cli/api/catalog.js:218
        return catalogs[locale][key].translation;
                               ^

TypeError: Cannot read property 'hello.world' of undefined
```
I then looked into the cause of this error, and [HIDDEN] default value for `fallbackLocales` with my locales is contains:

```JSON
{
  "en-US": "en",
  "en-CA": "en"
}
```
It therefore fails, since locale `en` does not exist.
Which from the documentation is to be expected. I then attempted to set `fallbackLocales` to `false`, as also mentioned in the documentation. However that just provoked a new error
```
/.../node_modules/@lingui/cli/api/catalog.js:223
        var fL = fallbackLocales[locale]; // some probably the fallback will be undefined, so just search by locale

TypeError: Cannot read property 'en-CA' of null
```
This error looks to be caused by lack of check if `fallbackLocales` is defined or not.

I then tried setting the default fallback locale.
```JSON
"fallbackLocales": {
  "default": "en-US"
},
```
But that had no effect as for some reason the `fallbackLocales` object still contained the default values and now looked like this
```JSON
{
  "default": "en-US",
  "en-US": "en",
  "en-CA": "en"
}
```
I then tried to explicitly override the default values:
```JSON
"fallbackLocales": {
  "default": "en-US",
  "en-US": "en-US",
  "en-CA": "en-US"
},
```
However `fallbackLocales` remained unchanged.

So now I am at a loss. I am more than happy to correct some of these errors myself and submit a PR, but I can not do so before I know how it should work.

### Additional contract requirements

- When an untranslated message falls back to a locale that is not among the configured locales, the catalog translation lookup must not throw and must return a truthy result.
- Explicitly configured per-locale fallback values must be preserved rather than replaced by automatically derived parent-locale values.
- Setting `fallbackLocales` to `false` must not cause an exception, and compilation must still succeed. If a message is untranslated and no fallback is enabled, use its source-language message text as the compiled value.
