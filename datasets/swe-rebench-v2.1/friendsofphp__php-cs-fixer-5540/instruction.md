[psr_autoloading] Configuration must be an array and may not be empty.
## Bug report

updating from 2.18.2 to 2.18.3 we get the error when running `php-cs-fixer fix`

> [psr_autoloading] Configuration must be an array and may not be empty.

this feels like a bug, because the docs mention this setting can be null or string

https://cs.symfony.com/doc/rules/basic/psr_autoloading.html



### Code snippet that reproduces the problem

config

```php
<?php

$finder = PhpCsFixer\Finder::create()
    ->in([
        __DIR__.'/app',
        __DIR__.'/config',
        __DIR__.'/lib',
        __DIR__.'/models',
        __DIR__.'/public',
        __DIR__.'/scripts',
    ])
;

return PhpCsFixer\Config::create()
    ->setUsingCache(true)
    ->setRules([
        '@Symfony' => true,
        '@Symfony:risky' => true,
        'array_syntax' => ['syntax' => 'short'],
        'fopen_flags' => false,
        'ordered_imports' => true,
        'protected_to_private' => false,
        'list_syntax' => ['syntax' => 'long'], // 'short' requires php 7.1+

        // custom rules for Motion
        // We need to disable psr_autoloading because it will change the classnames otherwise. PSR-0 autoloading is no solution!
        'psr_autoloading' => null,
    ])
    ->setRiskyAllowed(true)
    ->setFinder($finder)
;
```

### Additional contract requirements

- When a rule is given an invalid value, the error message must be `[foo] Rule must be enabled (true), disabled (false) or configured (non-empty, assoc array). Other values are not allowed.`
- A rule configured with `null` must be accepted and treated as disabled, instead of being rejected as an invalid configuration.
