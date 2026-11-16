no-console parameters are converted wrong (black list vs white list)
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: master
See current test:
https://github.com/typescript-eslint/tslint-to-eslint-config/blob/43d3a554d9fa3acf3f1d4beafb5fa57700e7a2f8/src/rules/converters/tests/no-console.test.ts

#### Actual Behavior

`"no-console": [true, "log", "error"]`
is converted to
````
 "no-console": [
         "error",
         {
            "allow": [
               "log",
               "error"
            ]
         }
      ],
````
tslint no-console parameter are a [blacklist](https://palantir.github.io/tslint/rules/no-console/). but eslint parameter only allows a [whitelist](https://eslint.org/docs/rules/no-console#disallow-the-use-of-console-no-console).
