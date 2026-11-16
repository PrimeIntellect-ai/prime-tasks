Implement currency formatting with long display names.
Namely, things like:

    "123,456.78 US dollars"

(en locale)

or

    "dólares estadounidenses 123,456.78"

(es-GT locale)

The algorithm for doing this is described here: https://www.unicode.org/reports/tr35/tr35-numbers.html#Currencies and CLDR contains the data.

I'd be happy to attempt to implement this myself. Two issues I'm aware of:

1) What should the API be? An extra parameter to `format_currency`? A new `format_type` (this risks clashing with other format types already defined)?

2) It looks like this would require data not currently available in the pickled locale data. Specifically it requires the `unitPattern` data. I'm not sure how to go about adding this - apart from the `import_cldr.py` script, is there a specific process to follow?

For comparison, browsers currently implement this as part of [Intl.NumberFormat](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/NumberFormat) using options `{currencyDisplay: "name"}`. In a browser console you can do:

    > Intl.NumberFormat("en", {currencyDisplay:"name", style:"currency", currency:"USD"}).format(123456.78)
    "123,456.78 US dollars"

### Additional contract requirements

- `format_currency` accepts `format_type='name'`, which produces the long display name form. The existing `format` and `currency_digits` parameters of `format_currency` continue to control the numeric part.
- Add a public function `get_currency_unit_pattern(currency, count=None, locale=...)` in module `babel.numbers`. It returns a string pattern containing `{0}` where the formatted number is substituted and `{1}` where the currency's long display name is substituted. The pattern reflects the locale's ordering of the number and the name, and the plural form selected by `count`. When `count` is omitted, the generic "other" pattern is returned.
