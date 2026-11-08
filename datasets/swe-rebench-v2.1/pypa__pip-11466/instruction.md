virtualenv with --system-site-packages breaks pip's build isolation
It seems that if you create a virtualenv with `--system-site-packages`, the system packages (but *not* the user packages) will be on the `PYTHONPATH` in the PEP 517 isolated build environment that `pip` creates (it does not effect `python -m pep517.build`), and it seems they will be on there with *higher precedence* than the requirements installed in the build environment. It only affects `pip >= 19.0.0`.

The most common way I've seen this cause problems is with the new `setuptools.build_meta:__legacy__` backend. Since the most recent version of `pip` requires a recent version of `setuptools`, if you have an older version of `setuptools` installed on the system, `pip install` will fail due to the missing `setuptools.build_meta:__legacy__` backend. It is possible to reproduce this by crafting a deliberately bad package and installing it, then creating a wheel for a newer version of the package (which allowed me to test that this failure was actually introduced with `pip==19.0.0`), but for the MWE we can stick with `setuptools`.

To reproduce, create a package like this:

```bash
cd /tmp
mkdir demo
cd demo
mkdir badpkg

touch badpkg/pyproject.toml
echo 'from setuptools import setup; setup(name="foo", version="0.1.0")' \
    > badpkg/setup.py
```

Then install an older version of `setuptools` *on your system* (can't be `--user` or in the virtualenv), `pip install 'setuptools < 40.8.0'` (I did this in a `pyenv` environment). If your system already has an older version of `setuptools` on it, you're already good.

Next create a virtualenv with `--system-site-packages` and activate it:

```bash
virtualenv venv --system-site-packages
source venv/bin/activate
```

Finally try to install `badpkg` (`pip wheel` or `pip install -t tmp` also works to demonstrate the problem):

```bash
pip install ./badpkg
```

You should get a traceback the ends like this:

>  `AttributeError: module 'setuptools.build_meta' has no attribute '__legacy__'`

At first I thought this was because the affected packages had too loose bounds on `build-system.requires` (e.g. `requires=["setuptools"]`) and that `pip` was failing to install a more recent version in the isolated environment, but this bug still occurs even if you specify `"setuptools>=40.8.0"`, so I believe it's not a problem at install-time, it's a problem with the path resolution at build time.

At the moment it's unclear if this is a problem with `pip` or `virtualenv`, but since it does not affect `python -m pep517.build`, I'm reporting it here. It could be a combination of both.

CC: @gaborbernat
