Check data types in default CoreExtension
I am currently upgrading a project for PHP 8.1. I get lot of mb_strtolower(): Passing null to parameter #1 ($string) of type string is deprecated in vendor/twig/twig/src/Extension/CoreExtension.php on line 1098

It's pretty hard to find which template/variable is triggern this. Maybe it makes sense to check the type in the CoreExtension and throw an error?

### Additional contract requirements

- `null` is an accepted value for the string filters `capitalize`, `convert_encoding`, `escape`, `first`, `last`, `lower`, `replace`, `reverse`, `spaceless`, `split`, `title`, `trim`, `upper` and `url_encode`. Rendering a template that passes `null` to any of them must not raise a PHP deprecation or error; the output must be the same as for an empty string.
- `null` is also accepted by `round` and `number_format`, where it is treated as `0`, and must not raise a PHP deprecation or error.
