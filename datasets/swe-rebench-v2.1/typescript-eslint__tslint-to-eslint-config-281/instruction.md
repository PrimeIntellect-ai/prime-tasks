`@typescript-eslint/member-delimiter-style` and `padding-line-between-statements` rules are broken
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: 0.3.1
-   ESLint version: 6.7.2
-   Node version: 12.6.0

#### Actual Behavior

1. Prepare tslint.json

`tslint.json`

```json
{
    "rules": {
        "newline-before-return": true,
        "semicolon": [true, "always"]
    }
}
```

2. Run tslint-to-eslint-config

`npx tslint-to-eslint-config@0.3.1`

3. A broken config file is generated

`.eslintrc.js`

```javascript
module.exports = {
    "env": {
        "es6": true,
        "node": true
    },
    "extends": [],
    "parser": "@typescript-eslint/parser",
    "parserOptions": {
        "project": "tsconfig.json",
        "sourceType": "module"
    },
    "plugins": [
        "@typescript-eslint"
    ],
    "rules": {
        "@typescript-eslint/member-delimiter-style": [
            "error",
            "error",
            {
                "multiline": {
                    "delimiter": "semi",
                    "requireLast": true
                },
                "singleline": {
                    "delimiter": "semi",
                    "requireLast": false
                }
            }
        ],
        "@typescript-eslint/semi": [
            "error",
            "always"
        ],
        "padding-line-between-statements": [
            "error",
            "error",
            {
                "blankLine": "always",
                "prev": "*",
                "next": "return"
            }
        ]
    },
    "settings": {}
};
```

#### Expected Behavior

```
        "@typescript-eslint/member-delimiter-style": [
            "error", // delete this line
            "error",
            {
                "multiline": {
                    "delimiter": "semi",
                    "requireLast": true
                },
                "singleline": {
                    "delimiter": "semi",
                    "requireLast": false
                }
            }
        ],
```

```
        "padding-line-between-statements": [
            "error", // delete this line
            "error",
            {
                "blankLine": "always",
                "prev": "*",
                "next": "return"
            }
        ]
```

#### Reproduction

---

```bash
#!/bin/bash
mkdir example
cd example/
npm init -y
npm i -D typescript tslint
cat <<EOS >tslint.json
{
    "rules": {
        "newline-before-return": true,
        "semicolon": [true, "always"]
    }
}
EOS
npx tslint-to-eslint-config@0.3.1
cat .eslintrc.js
```
