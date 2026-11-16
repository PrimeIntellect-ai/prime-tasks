Fixer breaks PhpDoc before return
## Bug report

<!--
  Before reporting a bug, make sure PHP CS Fixer is up-to-date.

  Check that the issue is NOT regarded to an applied rule by using the `-vvv` option (will list applied rules) on a minimal code snippet.
-->

### Description

<!--
  Please describe the problem.
-->
`phpdoc_to_comment` rule breaks PhpDoc that is used to declare returned value from within a function.

### Runtime version

<!--
   Provide PHP CS Fixer version and PHP runtime by sharing result of this command:
   $ php-cs-fixer -V
-->
PHP CS Fixer 3.28.0 Jump & Run by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 8.2.11

### Used command

<!--
   Provide the command used to run PHP CS Fixer (run with `-vvv`).
-->
`php ./vendor/bin/php-cs-fixer fix --allow-risky=yes --config=.php-cs-fixer.dist.php`

```
Loaded config default from ".php-cs-fixer.dist.php".
Using cache file "/srv/app/var/tools/.php-cs-fixer.cache".
.........F................................................                                                                                                                                                                  58 / 58 (100%)
Legend: .-no changes, F-fixed, S-skipped (cached or empty file), I-invalid file syntax (file ignored), E-error
   1) /srv/app/src/Infrastructure/State/Order/OrderGetCollectionProvider.php (phpdoc_to_comment)

Fixed 1 of 58 files in 0.743 seconds, 16.000 MB memory used
```

### Configuration file

<!--
   Provide content of configuration file you used (.php-cs-fixer[.dist].php).
-->

```php
<?php

$finder = (new PhpCsFixer\Finder())
    ->in(__DIR__.'/src')
    ->in(__DIR__.'/tests')
    ->in(__DIR__.'/migrations')
;

return (new PhpCsFixer\Config())
    ->setRiskyAllowed(true)
    ->setRules([
        '@Symfony' => true,
        '@Symfony:risky' => true,
        '@DoctrineAnnotation' => true,
    ])
    ->setFinder($finder)
    ->setCacheFile(__DIR__.'/var/tools/.php-cs-fixer.cache')
;
```

### Code snippet that reproduces the problem

<!--
  Provide a minimal code snippet before running PHP CS Fixer. If relevant,
  also provide the expected output, the actual output and/or the error that
  occurred, if any.

  Please use markdown syntax for each code snippet, e.g.:

  ```php
  <?php
  $var = 'foo';
  ```
-->
Expected:
```php
<?php

function something(): object
{
    /** @var object */
    return $this->get();
}
```
Actual:
```php
<?php

function something(): object
{
    /* @var object */
    return $this->get();
}
```

### Additional contract requirements

- In the reproducer above, the expected output is the result when `allow_before_return_statement` is enabled. With the option omitted (its default), the shown PHPDoc immediately before `return` is converted as in the reported actual output.

- The `phpdoc_to_comment` fixer must support the boolean option `allow_before_return_statement`, whose default value is `false`. When the option is set to `true`, the fixer must preserve PHPDoc immediately before a `return` statement; when the option is set to `false` or omitted (the default), the fixer must convert it to a regular comment.
