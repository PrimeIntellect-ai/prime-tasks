`no-deprecated-modulo-syntax` rule
<!--
  Before proposing new rule, please make sure it hasn't been posted already.
  You can see all open propositions here:
  https://github.com/intlify/eslint-plugin-vue-i18n/issues?q=is%3Aissue+is%3Aopen+label%3A%22Type%3A+Feature%22
-->

**Please describe what the rule should do:**
<!-- A clear and concise description of what the rule should do. -->
vue-i18n v10 will drop modulo Interpolation (rails-style interpolation).
docs is here:
https://vue-i18n.intlify.dev/guide/essentials/syntax.html#rails-i18n-format

I would like to provide this rule to support migration, and support with `--fix` in this rule too.

**What category should the rule belong to?**
<!-- (place an "X" next to just one item) -->

- [x] Enforces code style (layout)
- [x] Warns about a potential error (problem)
- [ ] Suggests an alternate way of doing something (suggestion)
- [ ] Other (please specify:)

**Provide 2-3 code examples that this rule should warn about:**

✗ BAD :
```json
{
  "hello": "%{msg} world"
}
```

✓ GOOD:
```json
{
  "hello": "{msg} world"
}
```

**Additional context**
Not really relevant to this eslint plugin, but I will output a warning with message-compiler if it is also using modulo.

### Additional contract requirements

- For each deprecated modulo interpolation, report with the exact message `The modulo interpolation must be enforced to named interpolation.` and highlight the complete interpolation, including the leading `%`.
- Add a public function `getRuleTesterTestCaseOptions(root: string)` in module `tests/lib/test-utils.ts`. It returns an object with `json()`, `yaml()`, and `vue()` factory methods; the `json()` and `yaml()` results include a locale-file glob in `settings['vue-i18n'].localeDir.pattern`.
