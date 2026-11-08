space-within-parens converts 0 spaces incorrectly
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.5.1

#### Actual Behavior

```yaml
  space-within-parens:
    options:
      - 0
```

Is converted into `space-in-parens: always`

#### Expected Behavior

It should be converted into `space-in-parens: never`

#### Reproduction

See PR for reproduction.
