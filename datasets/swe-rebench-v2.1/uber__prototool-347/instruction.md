Allow Java Packages with tld prefixes other than COM
We've just started using prototool on a new project, and trying to adopt the `uber2` linting rules. We're running into a violation on the `FILE_OPTIONS_EQUAL_JAVA_PACKAGE_COM_PREFIX` rule, because our reverse dns is `au.com.<company>`, not `com.<company>`. I imagine that this would be a fairly common case for non-US based/non-global companies.

Ideally we'd like to be able to use the `uber2` ruleset without any rule exceptions, but mandating that Java packages start with `com` requires this rule to be disabled. If other tlds were supported, or the package prefix was overridable, this would allow the `uber2` ruleset to be used without exceptions.

I'm uncertain whether keeping the ability to use protos defined by other parties with different tlds would be required if overriding the package prefix.

### Additional contract requirements

- The Java package prefix is configurable through the `java_package_prefix` key under the `lint` section of the prototool configuration file. When set, the `java_package` file option is expected to be `<java_package_prefix>.<package>` instead of `com.<package>`, and this prefix is used by `lint`, `create`, and `format --fix`.
- Add a public function `JavaPackagePrefixOverride(packageName string, prefixOverride string) string` in `internal/protostrs/protostrs.go` that returns an empty string when `packageName` is empty, `<prefixOverride>.<packageName>` when `prefixOverride` is non-empty, and `com.<packageName>` otherwise.
