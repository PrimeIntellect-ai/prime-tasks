`_wrap_method` breaks doctest's ability to find class methods
Hello!

I recently noticed that many of the doctests I wrote were never executed. After digging a bit, it seems that doctest is [not able to find methods](https://docs.python.org/3/library/doctest.html#which-docstrings-are-examined) inside subclasses of `eqx.Module`.

Unfortunately, I did not find a fix yet, but I thought it would be important to report this, and maybe you already know some fix?

E.g., the following code:

```python
import equinox as eqx


class Example(eqx.Module):
    def foo(self) -> int:
        """
        >>> example = Example()
        >>> example.foo()
        1
        """
        return 1

    @property
    def bar(self) -> int:
        """
        >>> example = Example()
        >>> example.bar
        1
        """
        return 1

    @classmethod
    def baz(self) -> int:
        """
        >>> Example.baz()
        1
        """
        return 1

    @eqx.filter_jit
    def biz(self) -> int:
        """
        >>> example = Example()
        >>> example.biz()
        1
        """
        return 1

class Expected:
    def foo(self) -> int:
        """
        >>> example = Expected()
        >>> example.foo()
        1
        """
        return 1

    @property
    def bar(self) -> int:
        """
        >>> example = Expected()
        >>> example.bar
        1
        """
        return 1

    @classmethod
    def baz(self) -> int:
        """
        >>> Expected.baz()
        1
        """
        return 1

if __name__ == "__main__":
    import doctest
    doctest.testmod()
```

will never test doctests inside `Example.foo`'s docstring, but all other methods will be tested.

```
(equinox-doctest) ➜  equinox-doctest git:(master) ✗ uv run python example.py -v
Cannot read termcap database;
using dumb terminal settings.
Trying:
    example = Example()
Expecting nothing
ok
Trying:
    example.bar
Expecting:
    1
ok
Trying:
    Example.baz()
Expecting:
    1
ok
Trying:
    example = Example()
Expecting nothing
ok
Trying:
    example.biz()
Expecting:
    1
ok
Trying:
    example = Expected()
Expecting nothing
ok
Trying:
    example.bar
Expecting:
    1
ok
Trying:
    Expected.baz()
Expecting:
    1
ok
Trying:
    example = Expected()
Expecting nothing
ok
Trying:
    example.foo()
Expecting:
    1
ok
6 items had no tests:
    __main__
    __main__.Example
    __main__.Example.__delattr__
    __main__.Example.__init__
    __main__.Example.__setattr__
    __main__.Expected
6 items passed all tests:
   2 tests in __main__.Example.bar
   1 tests in __main__.Example.baz
   2 tests in __main__.Example.biz
   2 tests in __main__.Expected.bar
   1 tests in __main__.Expected.baz
   2 tests in __main__.Expected.foo
10 tests in 12 items.
10 passed and 0 failed.
Test passed.
```

### Additional contract requirements

- For a method defined on an `eqx.Module` subclass, the class attribute that stores that method must report the original method's `__module__` and `__doc__`. In particular, `__doc__` must be `None` when the original method has no docstring.
- These attributes must be read-only: assigning to them raises `AttributeError`.
