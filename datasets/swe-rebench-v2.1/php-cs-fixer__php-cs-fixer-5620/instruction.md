Support phpDoc in `fully_qualified_strict_types`
First of all i know it's not a bug or really an issue, but i would like to have it as a feature request.
Reason for that, is currently using this fixer, leaves code base in inconsistent state.

If i use fully_qualified_strict_types to transforms imported FQCN parameters and return types in function arguments to short version, i would also expect that if it can also transforms for the types that are mentioned within Phpdoc.

When reporting an issue (bug) please provide the following information:

#### The PHP version you are using (`$ php -v`):
=> 7.1.16
#### PHP CS Fixer version you are using (`$ php-cs-fixer -V`):
=> 2.10.0

#### If applicable, please provide minimum samples of PHP code (as plain text, not screenshots):
 * before running PHP CS Fixer (no changes):
```php
/** @param \This\Is\Param\Namespace\User $x **/
public function beforePhpCsFixer(\This\Is\Param\Namespace\User $x, string $y): void
{
    // function body
}
```

 * with unexpected changes applied when running PHP CS Fixer:
```php
/** @param \This\Is\Param\Namespace\User $x **/
public function beforePhpCsFixer(User $x, string $y): void
{
    // function body
}
```

 * with the changes you expected instead:
```php
/** @param User $x **/
public function beforePhpCsFixer(User $x, string $y): void
{
    // function body
}
```

Thank you!

### Additional contract requirements

The fixer's existing `leading_backslash_in_global_namespace` option (default `false`) also applies to type names written inside PHPDoc annotations. When that option is enabled and the code is in the global namespace, an unqualified type name in a PHPDoc annotation is prefixed with a leading backslash, for example `@param DateTimeInterface $dateTime` becomes `@param \DateTimeInterface $dateTime`, `@return DateTimeInterface` becomes `@return \DateTimeInterface`, `@see DateTimeImmutable` becomes `@see \DateTimeImmutable`, and `@throws Exception` becomes `@throws \Exception`.
