Name length limits for features/scenarios/steps
This would be a nice rule to have. Maybe have it default to off, though.

### Additional contract requirements

- Add a rule named `name-length` in module `src/rules/name-length.js` that exposes a public function `run(parsedFile, unused, configuration)`.
- `parsedFile` is a parsed Gherkin Feature node and `configuration` is the rule's configuration object.
- `run` returns an array of error objects, each with `message` (string), `rule` (string, the rule name `name-length`), and `line` (number). It returns an empty array when there are no violations.
- The maximum name length defaults to 70 characters for `Feature`, `Step`, and `Scenario`.
- Per-element-type maximum lengths can be configured with the numeric keys `Feature`, `Step`, and `Scenario`; a configured value overrides the default for that element type.
- For each name that exceeds its maximum, the error `message` has exactly the format: `<element type> name is too long. Length of <actual name length> is longer than the maximum allowed: <maximum allowed length>`, where `<element type>` is `Feature`, `Step`, or `Scenario`.
