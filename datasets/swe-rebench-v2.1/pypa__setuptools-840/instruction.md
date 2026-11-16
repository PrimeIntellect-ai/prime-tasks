Warning not filtered as supposed to
The warning emitted for missing standard script name in [py36compat.py](https://github.com/pypa/setuptools/blob/master/setuptools/command/py36compat.py#L76) is not suppressed by [`manifest_maker.warn`](https://github.com/pypa/setuptools/blob/master/setuptools/command/egg_info.py#L558) but seems to be supposed to.

I found this while exploring a setup.py as a directory containing a `__main__.py`.  I happened to run

```
python setup.py/__main__.py
```

and I had a warning about the file `__main__.py` missing.

You can suppress the warning by using the `script_name` keyword argument of `setuptools.setup` like so:

```
from setuptools import setup

setup(
    name="mypackage",
    # ... a plethora of other kwargs
    script_name="setup.py"
)
```
