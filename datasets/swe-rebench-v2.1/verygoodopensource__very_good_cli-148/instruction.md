feat: Add to the create command --org flag to name the package
**Description**
To avoid changing the package name and package identifier after the project is created, example:
`very_good create --org com.yourdomain appname`

### Additional contract requirements

- The organization flag is named `--org-name`.
- An organization name must have exactly three dot-separated parts. Each part may contain only letters, digits, or underscores. The two-part `com.yourdomain` value in the upstream usage example does not satisfy this rule; for example, `com.yourdomain.app` has the required number of parts.
- Reject each of these values when provided with `--org-name`: `My App`, `very.bad.test.case`, and `very%.bad@.#test`. The command exits with the usage exit code (64) and reports exactly the following message, substituting the supplied value for `{name}`:

```text
"{name}" is not a valid org name.

A valid org name has 3 parts separated by "."and only includes alphanumeric characters and underscores(ex. very.good.org)
```
