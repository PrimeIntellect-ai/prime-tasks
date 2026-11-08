`ParallelConfigFactory` using named parameters behaves unexpectedly when omiting first argument
### Problem description

```php
$config->setParallelConfig(ParallelConfigFactory::detect(processTimeout: 300));
```

:point_up: the above code will create unexpected parallel config values. `$processTimeout` argument will be used as number of files per process instead. [HIDDEN]

### Minimal reproducer

```php
$config = new \PhpCsFixer\Config();
$config->setParallelConfig(\PhpCsFixer\Runner\Parallel\ParallelConfigFactory::detect(processTimeout: 300));
```
or
```php
$config = new \PhpCsFixer\Config();
$config->setParallelConfig(\PhpCsFixer\Runner\Parallel\ParallelConfigFactory::detect(null, 300));
```

### Fixer version

3.57.1

### PHP version

8.3

### How do you run Fixer?

Composer package

### Contribution Checks

- [X] I have verified if this problem was already reported
- [X] I am familiar with ["Feature or bug?"](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/blob/master/feature-or-bug.rst)

### Additional contract requirements

When `filesPerProcess` and `processTimeout` are supplied by name, each value must configure its corresponding field. If only `processTimeout` is supplied by name, the files-per-process setting must retain its default. Supplying `null` as the first positional argument and a timeout as the second must configure that timeout, without treating it as the files-per-process setting.
