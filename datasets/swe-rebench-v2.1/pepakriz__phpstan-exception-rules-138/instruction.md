Native division does not throw ArithemticError
In #77 checks for ArithmeticError were added, however I don't think that native division (eg. `$x / $y`) can actually throw this. https://github.com/pepakriz/phpstan-exception-rules/issues/77#issuecomment-477955886 mentions only two ways to get the error:

> 1.    intdiv(PHP_INT_MIN, -1);
> 2.    1 << -3;

And the [PHP docs for ArithmeticError](https://www.php.net/manual/en/class.arithmeticerror.php) don't mention anything about native division.

If it's not possible for it to be thrown here, maybe we shouldn't be reporting it as an issue?
