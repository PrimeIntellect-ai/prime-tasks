PHP notice thrown when using tlint
I get the following notice repeatedly when using tlint:

```
PHP Notice:  Undefined property: PhpParser\Node\Expr\New_::$name in /Users/me/.composer/vendor/tightenco/tlint/src/Linters/RequestValidation.php on line 32
```

It doesn't hinder tlint from working but it doesn't look nice in the build-logs. :)
