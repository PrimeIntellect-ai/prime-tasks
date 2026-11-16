TypedDict removal causing breaking changes
On `4.14.0`, seeing this issue:

Python `3.12.10`:
```
# python -m pip install typing_extensions==4.14.0
Collecting typing_extensions==4.14.0
  Downloading typing_extensions-4.14.0-py3-none-any.whl.metadata (3.0 kB)
Downloading typing_extensions-4.14.0-py3-none-any.whl (43 kB)
Installing collected packages: typing_extensions
Successfully installed typing_extensions-4.14.0

# python
Python 3.12.10 (main, May 22 2025, 01:29:12) [GCC 12.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import typing
>>> import typing_extensions
>>>
>>> typing.Type[typing_extensions.TypedDict]
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/local/lib/python3.12/typing.py", line 398, in inner
    return func(*args, **kwds)
           ^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/typing.py", line 1481, in __getitem__
    params = tuple(_type_check(p, msg) for p in params)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/typing.py", line 1481, in <genexpr>
    params = tuple(_type_check(p, msg) for p in params)
                   ^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/typing.py", line 202, in _type_check
    raise TypeError(f"Plain {arg} is not valid as type argument")
TypeError: Plain typing_extensions.TypedDict is not valid as type argument

#
# Reverting to 4.13.0 works fine
#

# python -m pip install typing_extensions==4.13.0
Collecting typing_extensions==4.13.0
  Downloading typing_extensions-4.13.0-py3-none-any.whl.metadata (3.0 kB)
Downloading typing_extensions-4.13.0-py3-none-any.whl (45 kB)
Installing collected packages: typing_extensions
  Attempting uninstall: typing_extensions
    Found existing installation: typing_extensions 4.14.0
    Uninstalling typing_extensions-4.14.0:
      Successfully uninstalled typing_extensions-4.14.0
Successfully installed typing_extensions-4.13.0

# python
Python 3.12.10 (main, May 22 2025, 01:29:12) [GCC 12.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import typing
>>> import typing_extensions
>>>
>>> typing.Type[typing_extensions.TypedDict]
typing.Type[TypedDict]
>>>
```

Python `3.13.3`:
```
# python -m pip install typing_extensions==4.14.0
Collecting typing_extensions==4.14.0
  Downloading typing_extensions-4.14.0-py3-none-any.whl.metadata (3.0 kB)
Downloading typing_extensions-4.14.0-py3-none-any.whl (43 kB)
Installing collected packages: typing_extensions
Successfully installed typing_extensions-4.14.0

root@e4af1eca0c5e:/# python
Python 3.13.3 (main, May 22 2025, 01:27:26) [GCC 12.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import typing
... import typing_extensions
...
... typing.Type[typing_extensions.TypedDict]
...
Traceback (most recent call last):
  File "<python-input-0>", line 4, in <module>
    typing.Type[typing_extensions.TypedDict]
    ~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.13/typing.py", line 432, in inner
    return func(*args, **kwds)
  File "/usr/local/lib/python3.13/typing.py", line 1639, in __getitem__
    params = tuple(_type_check(p, msg) for p in params)
  File "/usr/local/lib/python3.13/typing.py", line 1639, in <genexpr>
    params = tuple(_type_check(p, msg) for p in params)
                   ~~~~~~~~~~~^^^^^^^^
  File "/usr/local/lib/python3.13/typing.py", line 200, in _type_check
    raise TypeError(f"Plain {arg} is not valid as type argument")
TypeError: Plain typing_extensions.TypedDict is not valid as type argument

#
# Reverting to 4.13.0 works fine
#

# python -m pip install typing_extensions==4.13.0
Collecting typing_extensions==4.13.0
  Downloading typing_extensions-4.13.0-py3-none-any.whl.metadata (3.0 kB)
Downloading typing_extensions-4.13.0-py3-none-any.whl (45 kB)
Installing collected packages: typing_extensions
  Attempting uninstall: typing_extensions
    Found existing installation: typing_extensions 4.14.0
    Uninstalling typing_extensions-4.14.0:
      Successfully uninstalled typing_extensions-4.14.0
Successfully installed typing_extensions-4.13.0

root@e4af1eca0c5e:/# python
Python 3.13.3 (main, May 22 2025, 01:27:26) [GCC 12.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import typing
... import typing_extensions
...
... typing.Type[typing_extensions.TypedDict]
...
typing.Type[TypedDict]

```
