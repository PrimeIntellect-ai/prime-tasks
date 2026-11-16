Casing function: allow hyphens or slashes
Casing for headers might need a Hyphenated-Pascal-Case and paths would need /slashSeperated/camelCase. Maybe we can get this into the casing function, through some sort of "separator" logic.

https://github.com/adidas/api-guidelines/pull/22

### Additional contract requirements

The casing rule must accept an optional `separator` option with a one-character `char` value for recognizing groups separated by that character. When `allowLeading` is true, the separator may also appear at the beginning. With this option, Pascal casing must recognize hyphen-separated header names such as `X-MyAmazing-Header`, and camel casing must recognize slash-separated paths beginning with `/`, such as `/path/to/myResource`. Existing casing modes and digit handling without this option remain unchanged.
