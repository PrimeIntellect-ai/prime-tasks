Extraneous spaces around double colon are not removed
There does not appear to be a setting that handles spacing around double colon, which I would like to have automatically removed.

----

#### The PHP version you are using (`$ php -v`):
```
PHP 7.2.10 (cli) (built: Nov 16 2018 15:24:33) ( NTS )
Copyright (c) 1997-2018 The PHP Group
Zend Engine v3.2.0, Copyright (c) 1998-2018 Zend Technologies
```

#### PHP CS Fixer version you are using (`$ php-cs-fixer -V`):
```
PHP CS Fixer 2.14.1 Sunrise by Fabien Potencier and Dariusz Ruminski (2e82abd)
```

#### The command you use to run PHP CS Fixer:
`php-cs-fixer fix --verbose --diff --dry-run`

#### The configuration file you are using, if any:
```php
<?php

declare(strict_types=1);

$finder = PhpCsFixer\Finder::create()
    ->exclude('var')
    ->ignoreDotFiles(false)
    ->name(basename(__FILE__))
    ->in(__DIR__)
;

return PhpCsFixer\Config::create()
    ->setRules([
        '@PHPUnit60Migration:risky' => true,
        '@DoctrineAnnotation' => true,
        '@Symfony' => true,
        '@Symfony:risky' => true,
        '@PHP71Migration' => true,
        '@PHP71Migration:risky' => true,
        '@PhpCsFixer' => true,
        '@PhpCsFixer:risky' => true,
        'array_syntax' => [
            'syntax' => 'short',
        ],
        'align_multiline_comment' => [
            'comment_type' => 'phpdocs_like',
        ],
        'concat_space' => [
            'spacing' => 'one',
        ],
        'explicit_indirect_variable' => true,
        'explicit_string_variable' => true,
        'linebreak_after_opening_tag' => true,
        'list_syntax' => [
            'syntax' => 'short',
        ],
        'method_argument_space' => [
            'on_multiline' => 'ensure_fully_multiline',
        ],
        'method_chaining_indentation' => true,
        'multiline_comment_opening_closing' => true,
        'no_alternative_syntax' => true,
        'no_binary_string' => true,
        'no_php4_constructor' => true,
        'no_superfluous_elseif' => true,
        'no_useless_else' => true,
        'ordered_imports' => true,
        'return_assignment' => true,
        'simplified_null_return' => true,
        'trim_array_spaces' => false,
    ])
    ->setIndent(str_repeat(' ', 4))
    ->setRiskyAllowed(true)
    ->setFinder($finder)
;
```

#### If applicable, please provide minimum samples of PHP code (as plain text, not screenshots):
 * before running PHP CS Fixer (no changes):
```php
$x = self:: FOOBAR;
```

 * with unexpected changes applied when running PHP CS Fixer:
```php
$x = self:: FOOBAR;
```

 * with the changes you expected instead:
```php
$x = self::FOOBAR;
```

### Additional contract requirements

- When whitespace after `::` is followed by a comment, preserve that whitespace. For example, `echo A\B   ::     /**/ c;` becomes `echo A\B::     /**/ c;`.
- The fixer class must be `PhpCsFixer\Fixer\Operator\NoSpaceAroundDoubleColonFixer`, and its rule name must be `no_space_around_double_colon`.
