Add provider `gj-IN` for Gujarati language
* Faker version:  <= 29.0.0
* OS: all

There is no provider for Gujarati language in faker


### Expected behavior

There should be a new provider

### Actual behavior

No Provider for `gj-IN`

### Additional contract requirements

- The provider is registered for the `gu_IN` locale.
- The `gu_IN` date_time provider exposes a public method `day_of_week_in_guj()` that returns the name of the current weekday written in Gujarati script.
- The `gu_IN` date_time provider exposes a public method `month_name_in_guj()` that returns the name of the current month written in Gujarati script.
- The `gu_IN` date_time provider exposes a public method `month_in_guj()` that returns a month name as a string; the returned value is either the localized Gujarati month name or the same value as `month_name()`.
