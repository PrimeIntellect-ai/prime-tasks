Add `Or` expression
While we already have the `And` expression, we cannot express `Or` expressions today.

### Additional contract requirements

Callers can combine filter expressions with OR: a record matches when either alternative matches. OR expressions can be nested with AND expressions, and the combined expression must retain those semantics.
