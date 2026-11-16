`single_space_around_construct` ignored for alternative syntax
### Problem description

The `single_space_around_construct` rule does not apply to `if` statements with [alternative syntax](https://www.php.net/manual/en/control-structures.alternative-syntax.php). If a file contains any alternative syntax, the `single_space_around_construct` rule is even skipped for the whole file.

Other rules seem to handle normal and alternative syntax equally. As far as I can tell the documentation of the `single_space_around_construct` rule does not exclude the alternative syntax. Therefor, this seems to be an unintentional bug.

I will open a PR with a possible fix in a few minutes.

### Minimal reproducer

file.php:
```
<?php if(true): ?>
    A
<?php elseif(false): ?>
    B
<?php else: ?>
    C
<?php endif; ?>
```

Command:
```
source/vendor/bin/php-cs-fixer fix --rules=single_space_around_construct file.php
```

Expected contents of file.php (notice space after `if` and `elseif`):
```
<?php if (true): ?>
    A
<?php elseif (false): ?>
    B
<?php else: ?>
    C
<?php endif; ?>
```

However, contents of file.php are unchanged.

### Fixer version

3.65.0

### PHP version

8.3.7

### How do you run Fixer?

Composer package

### Contribution Checks

- [X] I have verified if this problem was already reported
- [X] I am familiar with ["Feature or bug?"](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/blob/master/feature-or-bug.rst)

### Additional contract requirements

Alternative syntax in a file must not prevent the rule from correcting other configured constructs in that file that are applicable in normal syntax.
