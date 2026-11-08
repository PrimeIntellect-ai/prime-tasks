New Rule: Comment
As per [SCSS Lint](https://github.com/brigade/scss-lint/blob/master/lib/scss_lint/linter/README.md#comment)

* Prevent the use of multiline comments
* Allow a regular expression to override this check

### Additional contract requirements

* The rule is named `comment` and is configured like other rules (for example `comment: [1, { ... }]`).
* Every multiline comment (`/* ... */`) in a stylesheet produces one warning. Single-line `//` comments are never reported.
* The rule accepts an option named `allowed`, whose value is a list of regular expression strings. A multiline comment whose text matches at least one of these expressions is not reported; all other multiline comments are still reported.
