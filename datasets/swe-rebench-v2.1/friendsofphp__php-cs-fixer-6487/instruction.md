`return_assignment` can break functions that return by reference
## Bug report

<!--
  Before reporting a bug, make sure PHP CS Fixer is up-to-date.

  Check that the issue is NOT regarded to an applied rule by using the `-vvv` option (will list applied rules) on a minimal code snippet.

  Please describe the problem and provide technical details such as:
   * PHP CS Fixer version and PHP runtime: php-cs-fixer -V
   * the command used to run PHP CS Fixer (run with `-vvv`)
   * the configuration (file) you used
-->

When using the [`return_assignment`](https://github.com/FriendsOfPHP/PHP-CS-Fixer/blob/master/doc/rules/return_notation/return_assignment.rst) rule, it has an adverse effect if the function [returns by reference](https://www.php.net/manual/en/language.references.return.php).

Functions that return by reference must return a variable, but the `return_assignment` rule can rewrite function bodies that PHP throws an exception on.

This rule should avoid functions that return by reference.

```
vendor/bin/php-cs-fixer -V
PHP CS Fixer 3.8.0 BerSzcz against war! by Fabien Potencier and Dariusz Ruminski.
PHP runtime: 8.1.5
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

```php

class Example
{
    protected $myData;

    public function fallback()
    {
        return 'fallback';
    }

    public function &example($name)
    {
        if ($name == 'data') {
            $this->myData = 'something';

            return $this->myData;
        }

        $value = $this->fallback();

        return $value;
    }
}
```

With `return_assignment` enabled, the code gets condensed to:

```php

class Example
{
    protected $myData;

    public function fallback()
    {
        return 'fallback';
    }

    public function &example($name)
    {
        if ($name == 'data') {
            $this->myData = 'something';

            return $this->myData;
        }

        return $this->fallback();
    }
}
```

But that's problematic, because PHP complains:
> Only variable references should be returned by reference
