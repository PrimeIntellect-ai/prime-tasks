Add an option to exclude webhooks from operation-4xx-response rule
**Is your feature request related to a problem? Please describe.**
In terms of our [operation-4xx-response/](https://redocly.com/docs/cli/rules/operation-4xx-response/) rule we treat webhooks the same as path items (as it's intended by the spec).
However, webhooks ofter times are treated differently than path items so it makes sense to provide an option to exclude them from the rule.

**Describe the solution you'd like**
Add an option to exclude webhooks from the operation-4xx-response rule and similar ones.

**Describe alternatives you've considered**
Avoid applying the rule to the webhooks at all.

**Additional context**
https://redoc-ly.slack.com/archives/C02UHE7EL3E/p1669127864676219

### Additional contract requirements

The analogous rule covered by this request is `operation-2xx-response`. Both `operation-4xx-response` and `operation-2xx-response` support a `validateWebhooks` boolean rule option: when true, webhook operations are checked; when false, webhook operations are excluded. No default value is required by this contract. The option affects webhook operations only; path-item operations continue to be validated when the option is either true or false.
