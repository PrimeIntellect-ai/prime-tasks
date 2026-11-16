Support "default" as value for "// phpcs:set ... minimum_wp_version"
## Is your feature request related to a problem?
Looking at the repeated `// phpcs:set WordPress.WP.AlternativeFunctions minimum_wp_version 5.8` reset comments in a [test file](https://github.com/WordPress/WordPress-Coding-Standards/blob/feature/alternativefunctions-phpcsutils-and-modern-php/WordPress/Tests/WP/AlternativeFunctionsUnitTest.inc), then it seems like it's an ever-increasing list of places in code where future updates would need to be made when the default value changes, which could lead to some being missed.

## Describe the solution you'd like
I wondered if something like `// phpcs:set WordPress.WP.AlternativeFunctions minimum_wp_version default` could be supported (and perhaps similar for any other numerical/version/often-changing values), such that the consuming sniff(s) could look up the `default` value in a single place and use the actual value. It centralises the default value for that WPCS release.

## Additional context (optional)
Very much an internally-facing potential improvement, which may not warrant the extra complexity, even if it was possible, which I'm not sure it is, as it may just be assigning a value to a class property - maybe a magic `__set()` in the [new trait](https://github.com/WordPress/WordPress-Coding-Standards/blob/develop/WordPress/Helpers/MinimumWPVersionTrait.php) could be used?

[HIDDEN]

### Additional contract requirements

- For every sniff that uses `minimum_wp_version`, a value of `default` resolves to that sniff’s configured default WordPress version, including consumers other than AlternativeFunctions and Capabilities.
