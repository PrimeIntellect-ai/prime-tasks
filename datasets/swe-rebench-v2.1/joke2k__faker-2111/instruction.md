Add provider `gj-IN` for Gujarati language
* Faker version:  <= 29.0.0
* OS: all

There is no provider for Gujarati language in faker


### Expected behavior

There should be a new provider

### Actual behavior

No Provider for `gj-IN`

### Additional contract requirements

- The Gujarati provider is registered under the locale code `gu_IN`: the module is
  `faker.providers.person.gu_IN` and it defines a class named `Provider`. Selecting the
  locale with `Faker("gu_IN")` uses this provider.
- The provider defines the standard person-name collections `first_names`,
  `first_names_male`, `first_names_female`, `last_names`, `prefixes`, `prefixes_male`,
  and `prefixes_female`, and supports the standard person methods `first_name`,
  `first_name_male`, `first_name_female`, `last_name`, `name`, `prefix`, `prefix_male`,
  and `prefix_female`.
