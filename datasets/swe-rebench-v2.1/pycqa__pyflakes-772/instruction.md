F811 redefinition: false positive
Hi,

the following MWE
```python
def no_redef(value):
    if value:

        def fun(x, y):
            return x

    else:

        def fun(x, y):
            return y

    return fun


def redef(value):
    match value:
        case True:

            def fun(x, y):
                return x

        case False:

            def fun(x, y):
                return y

    return fun
```
throws the following warning:
```
redef.py:24:13: redefinition of unused 'fun' from line 19
```
i.e. pyflakes complains that the second `def fun` in the `redef` function is a redefinition of the previous definition. In my understanding both functions, `redef` and `no_redef` should be valid.

I use this version of pyflakes:
```
pyflakes --version
3.0.1 Python 3.10.8 on Linux
```

Constantin
