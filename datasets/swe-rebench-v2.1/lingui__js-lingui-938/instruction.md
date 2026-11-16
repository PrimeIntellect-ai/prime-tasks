Warnings for compilerBabelOptions other than empty.
**Describe the bug**
When using anything other than `compilerBabelOptions: {}` in my lingui configuration, I am issued a warning.

**To Reproduce**

create a lingui configuration file with

```json
{
    "compilerBabelOptions": {
      "minified": false
    },
    "locales": ["en"]
}
```

and run `npm run extract`, to be served with:

```none
● Validation Warning:

  Unknown option "compilerBabelOptions.minified" with value false was found.
  This is probably a typing mistake. Fixing it will remove this message.

Documentation: https://lingui.js.org/ref/conf.html
● Validation Warning:

  Unknown option "compilerBabelOptions.minified" with value false was found.
  This is probably a typing mistake. Fixing it will remove this message.

Documentation: https://lingui.js.org/ref/conf.html
```

`npm run compile` produces the same message, albeit just once.

**Expected behavior**

The configuration is correct, and should not result in a warning.

**Additional context**

- jsLingui version ``lingui --version``: 3.3.0

[HIDDEN]

### Additional contract requirements

- The default value of `compilerBabelOptions` in the resolved configuration must be exactly:

  ```json
  {
    "minified": true,
    "jsescOption": {
      "minimal": true
    }
  }
  ```

- A valid non-empty `compilerBabelOptions` configuration (for example `{ "minified": false }`) must not produce a validation warning.
