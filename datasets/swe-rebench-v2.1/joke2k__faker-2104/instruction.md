slug() - returns an empty string in some locales
* Faker version: 28.4.1
* OS: Mac

When using certain locales (e.g. `jp_JP`), the `slug` fake returns an empty string. I had a quick look and this is probably because the `slugify` decorator disallows unicode characters (which makes sense) and the fake is using the `text` fake under the hood - not anticipating that it is going to return unicode characters.

### Steps to reproduce

1. `fake = Faker("jp_JP")`
2. `fake.slug()`

### Expected behavior

The `slug` fake should never return an empty string

### Actual behavior

The `slug` fake returns an empty string in some locales.
