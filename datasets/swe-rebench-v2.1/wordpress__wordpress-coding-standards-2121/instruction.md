Remove deprecation Warning on sanitize_url()
## Bug Description

The use of sanitize_url() is still listed as deprecated, however as of WordPress 5.9 it has been **un** deprecated

## Minimal Code Snippet

Use sanitize_url() in a line of code.
ERROR   sanitize_url() has been deprecated since WordPress version 2.8.0. Use esc_url_raw() instead.
                  (WordPress.WP.DeprecatedFunctions.sanitize_urlFound)

[HIDDEN]

## Tested Against `develop` branch?

I have not tested against develop, but I did check here:

https://github.com/WordPress/WordPress-Coding-Standards/blob/develop/WordPress/Sniffs/WP/DeprecatedFunctionsSniff.php#L412

So it's still on the sniffs :)

### Additional contract requirements

- The Deprecated Functions sniff must not report `sanitize_url()` as deprecated, consistent with its undeprecation in WordPress 5.9.
