AbstractClassRestrictionsSniff fails to consider T_SELF, T_STATIC, maybe others before double-colon
<!--
PLEASE FILL OUT THE TEMPLATE COMPLETELY.
BUG REPORTS WHICH CANNOT BE REPRODUCED BASED ON THE INFORMATION PROVIDED WILL BE CLOSED.
-->

## Bug Description
<!--
Please provide a clear and concise description of what the bug is.

What did you expect to happen? What actually happened?
-->
This code
https://github.com/WordPress/WordPress-Coding-Standards/blob/dcbb3ec50911a554c9a4a7876dccb11419dda4e9/WordPress/AbstractClassRestrictionsSniff.php#L138-L142
is attempting to extract the class name from a static call like `Class::method()`, [HIDDEN]

I don't know whether there are other tokens that might also appear before a double-colon token and cause similar problems.

## Minimal Code Snippet
<!-- Please provide example code that allows us to reproduce the issue. Do NOT paste screenshots of code! -->

I'm not sure if this is the best reproduction, but it's where I started in tracking this down.

The issue happens when running this command:
```bash
vendor/bin/phpcs -s --standard=WordPress --sniffs=WordPress.WP.ClassNameCase test.php
```

... over a file containing this code:
```php
<?php

class Foo {
    public function bar() {
        wp_styles();
        self::foo();

        wp_styles();
        static::foo();
    }
}
```

## Error Code
<!--
The error code for the sniff that is (or should be) being triggered (you
can see the sniff error codes by running `phpcs` with the `-s` flag).
e.g. `WordPress.PHP.NoSilencedErrors.Discouraged`

You can leave this section empty if you are reporting a false negative.
-->
```
FILE: /tmp/test.php
------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FOUND 0 ERRORS AND 2 WARNINGS AFFECTING 2 LINES
------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 6 | WARNING | It is strongly recommended to refer to classes by their properly cased name. Expected: WP_Styles Found: wp_styles
   |         | (WordPress.WP.ClassNameCase.Incorrect)
 9 | WARNING | It is strongly recommended to refer to classes by their properly cased name. Expected: WP_Styles Found: wp_styles
   |         | (WordPress.WP.ClassNameCase.Incorrect)
------------------------------------------------------------------------------------------------------------------------------------------------------------------------
```

## Custom ruleset
<!--
If the issue cannot be reproduced when using `--standard=WordPress` on the command line,
please post the relevant part of your custom ruleset here.
-->

n/a

## Environment
<!--
To find out the versions used:
* PHP: run `php -v`.
* PHPCS: run `[vendor/bin/]phpcs --version`
* WPCS: run `composer [global] info` for a Composer install.
-->

| Question               | Answer
| ------------------------| -------
| PHP version             | 8.0.26
| PHP_CodeSniffer version | 3.7.1
| WPCS version            | dev-develop dcbb3ec
| WPCS install type       | Composer project local
| IDE (if relevant)       | None


## Additional Context (optional)
<!-- Add any other context about the problem here. -->
I don't think the `$local` parameter to `findPrevious()` on line 139 will be sufficient here, as it would still FP on something like `func( wp_styles(), self::method() )`.

## Tested Against `develop` branch?
- [x] I have verified the issue still exists in the `develop` branch of WPCS.

### Additional contract requirements

- Class-reference checks must not attribute a `self::...` or `static::...` access to an unrelated earlier expression, including when both occur within a containing call. Such accesses must not produce diagnostics based on that earlier expression.
