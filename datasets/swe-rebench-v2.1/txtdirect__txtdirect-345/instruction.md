[placeholders]: Default placeholders shouldn't overwrite custom placeholders
**Is this a BUG REPORT or FEATURE REQUEST?**:
bug

**What happened**:
Currently, the default placeholders would overwrite the named regex placeholders in case of a name collision.

**What you expected to happen**:
Use a new prefix for custom placeholders like named regex placeholders to avoid overwriting them.

**How to reproduce it (as minimally and precisely as possible)**:
Using the same names as default placeholders for named regex placeholder. like "host" and etc.

**Anything else we need to know?**:
What is the best prefix to use? suggestions:
- `{_my-named-regex}` "_"
- `{RE_my-named-regex}` "RE_"
- `{$my-named-regex}` "$"

**Environment**:
- TXTDirect version:  `master`

### Additional contract requirements

- Custom named-regex placeholders must use the `{$name}` syntax, with `$` as the prefix (for example, `{$a}` and `{$b}`).
