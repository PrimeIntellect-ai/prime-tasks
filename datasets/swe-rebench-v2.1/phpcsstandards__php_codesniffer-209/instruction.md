Squiz/VariableComment: incorrectly flags missing docblock for properties with union/intersection type
## Describe the bug

When scanning a class containing properties with PHP native union or intersection types, these will always be flagged as not having a docblock even when a docblock is present.

### Code sample
```php
class Foo
{
    /**
     * This is fine.
     *
     * @var string|integer
     */
    public $correct_not_missing_docblock_union;

    /**
     * This snippet gets flagged with "Missing member variable doc comment (Squiz.Commenting.VariableComment.Missing)"
     *
     * @var string|integer
     */
    public string|int $BUG_missing_docblock_with_union_type;

    /**
     * This is fine
     *
     * @var InterfaceA&InterfacB
     */
    public $correct_not_missing_docblock_intersection;

    /**
     * This snippet gets flagged with "Missing member variable doc comment (Squiz.Commenting.VariableComment.Missing)"
     *
     * @var InterfaceA&InterfacB
     */
    public InterfaceA&InterfacB $BUG_missing_docblock_intersection;
}
```


### To reproduce
Steps to reproduce the behavior:
1. Create a file called `test.php` with the code sample above...
2. Run `phpcs test.php --standard=squiz --sniffs=squiz.commenting.variablecomment`
3. See error message displayed
```
---------------------------------------------------------------------------------------------
FOUND 2 ERRORS AFFECTING 2 LINES
---------------------------------------------------------------------------------------------
 17 | ERROR | Missing member variable doc comment (Squiz.Commenting.VariableComment.Missing)
 31 | ERROR | Missing member variable doc comment (Squiz.Commenting.VariableComment.Missing)
---------------------------------------------------------------------------------------------
```

## Expected behavior
That the docblocks would be recognized correctly and no "missing docblock" errors would be thrown.

## Versions (please complete the following information)

| | |
|-|-|
| Operating System | _not relevant_
| PHP version | _not relevant_
| PHP_CodeSniffer version | `master`
| Standard | Squiz
| Install type | git clone

## Additional context
PR squizlabs/PHP_CodeSniffer#3757 may contain a partial fix for this.

## Please confirm:

- [x] I have searched the issue list and am not opening a duplicate issue.
- [x] I confirm that this bug is a bug in PHP_CodeSniffer and not in one of the external standards.
- [x] I have verified the issue still exists in the `master` branch of PHP_CodeSniffer.
