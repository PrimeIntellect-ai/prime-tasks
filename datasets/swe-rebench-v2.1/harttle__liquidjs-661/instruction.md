Array sum filter
hello hello, upstream ruby implementation has added [sum filter](https://github.com/Shopify/liquid/pull/1722) a while ago, I need it implemented here for compatibility and I assume this would be of your interest? I will attach a PR.

### Additional contract requirements

- The filter is named `sum` and is used in templates as `{{ arr | sum }}`.
- It accepts an optional property argument, used as `{{ arr | sum: "property" }}`. The property may be a dot-separated path such as `"age.first"` that selects a nested value from each element.
- Values that cannot be converted to a number count as `0` (for example a missing property, `null`, `undefined`, or a non-numeric string).
- The boolean `true` counts as `1`.
