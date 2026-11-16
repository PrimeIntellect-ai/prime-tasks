[Translator] No translations if detected via HTML lang attribute
Symfony locales are specified with an underscore to split country code from language code, e.g. `de_AT`.

When using UX Translator it correctly detects the current locale if set [via the HTML attribute](https://symfony.com/bundles/ux-translator/current/index.html#configuring-the-default-locale):

```twig
<html lang="{{ app.request.locale }}">
{# <html lang="de_AT"> #}
```

Unfortunately, [according to W3](https://www.w3.org/TR/html401/struct/dirlang.html#h-8.1.1), this format is invalid, as the "subcode" has to be separated by a hyphen.

Using

```twig
<html lang="{{ app.request.locale | replace({'_': '-'}) }}">
{# <html lang="de-AT"> #}
```

doesn't work, because this format is not detected by Translator, resulting in no translations at all (only the string constants are returned).

### Additional contract requirements

- The public function `getLocale()` exported by the `@symfony/ux-translator` package must return `de_AT` when `document.documentElement.lang` is `de-AT` or `de_AT`.
