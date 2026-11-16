Syntax error with tidy-imports after #263 (PyInf#11410)
Post the PR #263 , Syntax error is being raised with tidy-imports. Below is a simple reproducer

```
> cat /var/tmp/a.py
from very_very_very_long_named_package.very_long_named_module \
                                import(small_class, very_large_named_class as small_name)


> tidy-imports /var/tmp/a.py --no-remove-unused
...
SyntaxError: While processing /var/tmp/a.py: invalid syntax (<unknown>, line 2)

/usr/local/bin/tidy-imports: encountered the following problems:
    /var/tmp/a.py: SyntaxError: invalid syntax (<unknown>, line 2)
```

The reason is, the change made in #263 tries to sort the imports leaving it in some bad shape causing syntax error

```
from very_very_very_long_named_package.very_long_named_module import \

    small_class

from very_very_very_long_named_package.very_long_named_module import \

    very_large_named_class as small_name
```

Ideally snippet after sort should be
```
from very_very_very_long_named_package.very_long_named_module import \
    small_class
from very_very_very_long_named_package.very_long_named_module import \
    very_large_named_class as small_name
```
Note the empty lines in b/w
