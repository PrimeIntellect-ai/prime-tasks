black adds trailing comma despite using --target-version py35
Hi,

black 19.3b0 adds trailing commas for function signatures containing `*` despite setting target version 3.5. This creates invalid code for python 3.5 which will raise a SyntaxError. Setting
target version to py34 or using the auto detection doesn't add a trailing comma in this case.

```python3
def foo_func(bar, *, lorem=None, ipsum=None, dolor=None, sit=None, amet=None, consectetur=None):
    print('lorem ipsum dolor sit amet')
```
running
```sh
> black --target-version py35 --line-length 80 foo.py
```
creates

```python3
def foo_func(
    bar,
    *,
    lorem=None,
    ipsum=None,
    dolor=None,
    sit=None,
    amet=None,
    consectetur=None,
):
    print("lorem ipsum dolor sit amet")
```

Operating system: Ubuntu 18.04
Python version: Python 3.5/3.6
*Black* version:
```sh
> black --version
black, version 19.3b0
```
Does also happen on master: yes
