react/no-unknown-property: allow abbr on th
The `react/no-unknown-property` rule reports the `abbr` tag on `th` elements as invalid, which seems incorrect: https://developer.mozilla.org/en-US/docs/Web/HTML/Element/th#attr-abbr

### Additional contract requirements

- `abbr` must be allowed on both `<th>` and `<td>` elements.
- Using `abbr` on any other tag (for example `<div abbr="abbr" />`) must still be reported as invalid via the `invalidPropOnTag` message, whose list of allowed tags must be exactly `th, td` (in that order).
