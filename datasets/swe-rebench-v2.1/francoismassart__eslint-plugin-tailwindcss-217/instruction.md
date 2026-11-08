[BUG] classRegex ignored in vuejs
Hi,
Thanks for the great work!

**Describe the bug**
When in vueJS [templates case](https://github.com/francoismassart/eslint-plugin-tailwindcss/blob/893c44d288c07ed56d0dcaf7e5db10893854c03a/lib/util/ast.js#L41), the [checks are made](https://github.com/francoismassart/eslint-plugin-tailwindcss/blob/893c44d288c07ed56d0dcaf7e5db10893854c03a/lib/util/ast.js#L43) against `class` token, and not against the defined `classRegex`.

**To Reproduce**
Steps to reproduce the behavior:
1. Add classRegex to settings
2. Add classes to an attribute that is concerned by the regex.

**Expected behavior**
Any vue attributes concerned by classRegex should be validated.

**Environment (please complete the following information):**
 - OS: macOS
 - Eslint last version


Thanks!

### Additional contract requirements

In Vue templates, attributes matched by the configured `classRegex` must be treated as class-bearing attributes by every plugin rule that validates class attributes, not only by `no-custom-classname`.
