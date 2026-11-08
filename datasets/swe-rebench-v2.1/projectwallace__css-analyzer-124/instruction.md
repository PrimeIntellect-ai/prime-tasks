report selectors per rule
```css
.selector1,
.selector2 {
  // declarations
}

.selector1 {
  // declarations
}
```

```json
{
  "rules.selectors.avg": 1.5,
  "rules.selectors.max": 2
}
```

### Additional contract requirements

- The overall report exposes per-rule selector statistics under `rules.selectors.min`, `rules.selectors.max`, and `rules.selectors.average`. The `rules.selectors.avg` label in the displayed example refers to the same mean statistic; the report's field name is `rules.selectors.average`.
- The rules analyzer in module `src/analyzer/rules` returns `total`, `empty.total`, and `selectors.min`, `selectors.max`, and `selectors.average`; selector statistics are `0` when there are no rules.
- The parser in module `src/parser` returns a result whose `rules` array contains descriptors with `declarationsCount` and `selectorsCount`, where `selectorsCount` is the number of comma-separated selectors for the rule.
