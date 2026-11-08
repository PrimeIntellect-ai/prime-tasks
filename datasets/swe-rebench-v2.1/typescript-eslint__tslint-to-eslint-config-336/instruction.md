member-access does convert options correctly
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.5.1

#### Actual Behavior

```yaml
rules:
  member-access:
    options:
      - no-public
```

is converted into

```json
    "rules": {
        "@typescript-eslint/explicit-member-accessibility": [
            "error",
            {
                "accessibility": "explicit"
            }
        ]
    }
```

#### Expected Behavior

The accessibility should be `no-public`.
