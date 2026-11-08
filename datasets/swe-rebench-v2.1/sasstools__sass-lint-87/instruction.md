New Rule: Border Zero
As per [Scsslint](https://github.com/brigade/scss-lint/blob/master/lib/scss_lint/linter/README.md#borderzero) - option to enforce either the use of `border: 0` or `border: none`

### Additional contract requirements

The rule is available under the identifier `border-zero`. Users can configure its `convention` as either `'0'` or `'none'`; the selected spelling is accepted for zero border values, the other zero spelling is reported, and nonzero border values are not reported.
