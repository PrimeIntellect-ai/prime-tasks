Country-coded language codes breaks plurals when using po-gettext format
We are currently in the process of converting the localization of our application from 2-letter ISO Codes to 4-letter ISO Codes, and we use lingui for localizing all of our front-end applications.
We renamed all of PO files (`messages.en.po` -> `messages.en-CA.po`), and changed our `lingui.config.ts` `locales` from `en` to `en-CA`.

For the PO files content, following the [GNU Documents](https://www.gnu.org/software/gettext/manual/html_node/Header-Entry.html), the `Language` header can be in the following format;
> ‘ll_CC’, where ‘ll’ is an ISO 639 two-letter language code (lowercase) and ‘CC’ is an ISO 3166 two-letter country code (uppercase).

So we changed the `Language` header from `en` to `en_CA`.

**Describe the bug**
After changing the `Language` header in the PO files, the plurals couldn't be parsed correctly by `@lingui/loader`. We got the following error message:
`Multiple translations for item with key KEY in language en_CA, but no plural cases were found. This prohibits the translation of .po plurals into ICU plurals. Pluralization will not work for this key.`

[HIDDEN]

I was able to "fix" this issue by adding these couple of lines at the beginning of `getPluralCases(lang)`:
[HIDDEN]
But I am curious if it's a configuration issue on our side. I couldn't find anything in the docs explaining how to handle such a use-case (country-coded language codes + po-gettext format + plurals), but maybe there's an undocumented way of doing it?

**To Reproduce**
Using a PO file with a country-coded language code such as:
```
msgid ""
msgstr ""
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Language: en_CA\n"
"Plural-Forms: nplurals=2; plural=n != 1;\n"

msgid "test_key"
msgid_plural "test_key_plural"
msgstr[0] "# item"
msgstr[1] "# items"
```
and a country-coded language code in your `lingui.config.ts`, such as:
```
module.exports = {
    locales: ["en-CA"],
    sourceLocale: "en-CA",
    fallbackLocales: {
        default: "en-CA"
    },
    catalogs: [
        {
            path: "<rootDir>/src/locales/messages.{locale}",
            include: "<rootDir>/src",
            exclude: ["**/node_modules/**"]
        }
    ],
    format: "po-gettext",
    compileNamespace: "cjs",
};
```

You can simply run `lingui compile` and it should reproduce the error.


**Expected behavior**
It should find the correct plural cases for country-coded language codes, such as "en-CA" or "fr-CA".

- jsLingui version 3.10.4
- Babel version 7.12.9
