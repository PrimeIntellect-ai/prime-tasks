Two passes needed for no_superfluous_phpdoc_tags + phpdoc_add_missing_param_annotation
## Bug report

### Description

Two passes may be required if we use both `NoSuperfluousPhpdocTagsFixer` and `PhpdocAddMissingParamAnnotationFixer`.

### Runtime version

```
PHP CS Fixer 3.26.1 Crank Cake by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 7.4.33
```

### Configuration file

```php
<?php

$config = new PhpCsFixer\Config();

return $config
    ->setRules([
        'phpdoc_add_missing_param_annotation' => true
        'no_superfluous_phpdoc_tags' => true,
    ])
    ->setFinder(PhpCsFixer\Finder::create()
        ->in(__DIR__)
    )
;
```

### Code snippet that reproduces the problem

Let's assume we have this file:

```php
<?php

/**
 * @param int $bar Bar description
 * @param resource|null $baz=null Wrong baz description
 */
function foo($bar, $baz = null)
{
}
```

At the first pass, `NoSuperfluousPhpdocTagsFixer` changes it to

```php
<?php

/**
 * @param int $bar Bar description
 */
function foo($bar, $baz = null)
{
}
```

At the second pass, `PhpdocAddMissingParamAnnotationFixer` changes it to

```php
<?php

/**
 * @param int $bar Bar description
 * @param null|mixed $baz
 */
function foo($bar, $baz = null)
{
}
```

### Additional contract requirements

- The method `getVariableName()` on `PhpCsFixer\DocBlock\Annotation` returns a nullable string (`?string`). It returns the variable name found in the annotation, prefixed with `$`, or `null` when no variable name can be found. Only characters that are valid in a PHP variable name are part of the returned variable name; any characters that follow the variable name (for example `=null` or a description) are not part of it.
- When the `no_superfluous_phpdoc_tags` rule is applied, a `@param` tag that documents a parameter and carries a description is not removed as superfluous, even when the variable name is immediately followed by `=` (for example `@param resource|null $baz=null Wrong baz description`).
