switch_case_semicolon_to_colon fixer breaks match expressions
## Bug report

PHP CS Fixer 2.18.0 on PHP 8.0.1

If I run PHP CS Fixer on a file containing a match expression, that file is listed under

```
Files that were not fixed due to errors reported during linting after fixing
```

In verbose mode, I get the following error message:

```
[PhpCsFixer\Linter\LintingException]
Parse error: syntax error, unexpected token ":", expecting "," or ";" on line 7.

Applied fixers: switch_case_semicolon_to_colon
```

If I disable the mentioned `switch_case_semicolon_to_colon` fixer, the error is gone.

### Code snippet that reproduces the problem

```php
echo match (\PHP_MAJOR_VERSION) {
    8 => 'eight',
    9 => 'nine',
    default => 'unknown',
};
```
