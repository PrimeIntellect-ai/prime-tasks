Sass Syntax - Clean import paths issues
There are issues with the `clean-import-paths` rule when using the sass syntax as it's valid syntax to use without quotes. See guide http://sass-lang.com/guide

This in turn breaks the way we're detecting strings and validating them so a new way will need to be thought up.

### Additional contract requirements

- The `clean-import-paths` rule must detect and validate import paths written in Sass syntax without quotes (for example `@import foo`, `@import foo.scss`, `@import _foo`), applying the same `leading-underscore` and `filename-extension` checks that it applies to quoted imports.
- With the default options (`leading-underscore: false`, `filename-extension: false`), an unquoted Sass import whose path has a filename extension (e.g. `@import foo.scss`) or a leading underscore (e.g. `@import _foo`) is reported as exactly one violation, while a plain unquoted path (e.g. `@import foo`) is not reported.
- With `leading-underscore: true`, an unquoted Sass import without a leading underscore (e.g. `@import foo`) is reported as exactly one violation.
- With `filename-extension: true`, an unquoted Sass import without a filename extension (e.g. `@import foo`) is reported as exactly one violation.
