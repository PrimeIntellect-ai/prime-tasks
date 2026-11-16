singleLinePerProperty rule should support single-line definitions
My team just started using this linter and it has already helped out tremendously.  One rule we would like to see altered however, is the `singleLinePerProperty` rule.  By name, this sounds like a rule that we should support, but it causes a warning on simple lines of this format:

```
.ion-help-circled { cursor: pointer; }
```

I feel like there should be a separate rule governing whether or not you should be allowed to put attribute definitions on the same line as the selector.  As it stands, we have to disable this rule, even though we would like to be able to catch definitions that look like:

```
.section-title {
    font-size: 16px; margin-bottom: 20px;
}
```

### Additional contract requirements

- The `singleLinePerProperty` rule accepts an `allowSingleLineRules` option (boolean, default `false`). When it is `true`, a rule whose selector and its single declaration appear on the same line is not reported; when it is `false`, declarations that share a line with another declaration are reported.
- The public linter entry point `linter.lint(input, fullPath, config)` in `lib/linter.js` forwards rule-specific options, including `singleLinePerProperty.allowSingleLineRules`, to the underlying rule.
