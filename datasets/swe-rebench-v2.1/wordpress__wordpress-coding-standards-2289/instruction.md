False positive "High pagination limit" when `posts_per_page` is set to a function.
<!--
PLEASE FILL OUT THE TEMPLATE COMPLETELY.
BUG REPORTS WHICH CANNOT BE REPRODUCED BASED ON THE INFORMATION PROVIDED WILL BE CLOSED.
-->

## Bug Description
<!--
Please provide a clear and concise description of what the bug is.

What did you expect to happen? What actually happened?
-->

When setting `posts_per_page` to a function, wpcs logs "Detected high pagination limit, `posts_per_page` is set to..." warning.
It should [be treated like `-1`](https://github.com/WordPress/WordPress-Coding-Standards/issues/1638#issuecomment-459141404), and have no error shown.

## Minimal Code Snippet
<!-- Please provide example code that allows us to reproduce the issue. Do NOT paste screenshots of code! -->

The issue happens when running this command:
```bash
phpcs ...
```

... over a file containing this code:
```php
function get_query_args( int $first, int $last, int $default_min = 10 ) : array {
  return array(
    // other query args...
    'posts_per_page' => min( max( $first, $last ), $default_min ),
  );
}
```

## Error Code
<!--
The error code for the sniff that is (or should be) being triggered (you
can see the sniff error codes by running `phpcs` with the `-s` flag).
e.g. `WordPress.PHP.NoSilencedErrors.Discouraged`

You can leave this section empty if you are reporting a false negative.
-->
`WordPress.WP.PostsPerPage.posts_per_page_posts_per_page`

## Custom ruleset
<!--
If the issue cannot be reproduced when using `--standard=WordPress` on the command line,
please post the relevant part of your custom ruleset here.
-->

## Environment
<!--
To find out the versions used:
* PHP: run `php -v`.
* PHPCS: run `[vendor/bin/]phpcs --version`
* WPCS: run `composer [global] info` for a Composer install.
-->

| Question               | Answer
| ------------------------| -------
| PHP version             | 8.0.15
| PHP_CodeSniffer version | 3.6.2
| WPCS version            | 2.3.0, dev-develop
| WPCS install type       | Composer project local
| IDE (if relevant)       | VSCode on wsl2


## Tested Against `develop` branch?
- [x] I have verified the issue still exists in the `develop` branch of WPCS.

### Additional contract requirements

The `WordPress.WP.PostsPerPage` sniff must only report the "Detected high pagination limit" warning when the value assigned to `posts_per_page` (or `numberposts`) is a determinable number that exceeds the configured limit. The following value forms must be handled:

- Values whose numeric value cannot be determined from the source must be disregarded and must not produce a warning. This includes function calls, method calls, closures, array access, ternary expressions and array literals, for example `min( max( $first, $last ), $default_min )`, `$value[0][1]`, `$value ? 10 * $value : 300`, `get_value( name: 'post_per_page', type: 'query' )`, `my\get_posts_per_page()`, `[ 100, 200, 300 ]` and `array(100, 200, 300)`.
- String values that are not purely numeric must be disregarded and must not produce a warning, for example `'1e3'`.
- Purely numeric string values must be compared against the configured limit as integers, for example `'50'` is below the default limit of 100, while `'200'` and `"200"` are above it.
- Explicitly positive numbers must be compared against the configured limit, for example `+50` is below the default limit of 100, while `+200` is above it.
- Numbers written using a non-decimal base must be compared using their decimal value: binary `0b1001011` (75) and `0b10010110` (150), hexadecimal `0x4B` (75) and `0x96` (150), and octal `0113` (75), `0226` (150), `0O113` (75) and `0o226` (150).
- Numbers written using PHP 7.4+ numeric literal separators (`7_5` = 75, `1_50` = 150) and floating point numbers (`75.0` = 75, `150.000` = 150) must be compared using their decimal value.
