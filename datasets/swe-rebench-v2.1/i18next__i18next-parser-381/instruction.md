React - handle `t` when used as a tagged template
## 🚀 Feature Proposal

For React, support extraction when `t` is used as a tagged template (outside of being used as a normal function).

## Motivation

`t`, when used as a tagged template, offers a more concise syntax.

## Example

```tsx
const { t } = useTranslation();
<div>{t`Language`}<div>
```

### Additional contract requirements

- When a tagged-template key contains interpolations, emit a warning beginning with `A key that is a template string must not have any interpolations.`
