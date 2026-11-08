find_packages() doesn't find PEP 420 packages
Originally reported by: **gwideman (Bitbucket: [gwideman](http://bitbucket.org/gwideman), GitHub: [gwideman](http://github.com/gwideman))**

---

```
#!python

setup(...
    packages=find_packages(..)
    )
```

on the developer machine will fail to find packages that lack a `__init__.py` file, as is allowed in Python 3.3. However, such packages listed explicitly: packages=['mypkg'] do appear to get included and later installed.

Note: When testing this, before each test be sure to delete all generated metadata, including that which setup may previously have placed in the original source directory, as it seems that setup may use metadata created on a previous run in order to include files.

This is part of a general problem reported in issue #83, but I've logged it separately as it's specifically about setuptools.

---
- Bitbucket: https://bitbucket.org/pypa/setuptools/issue/97

### Additional contract requirements

- Add a public function `find_packages_ns` in the `setuptools` module, exposed as
  `setuptools.find_packages_ns` when running under Python 3.
- `find_packages_ns(where='.', exclude=(), include=('*',))` accepts an optional
  `where` search directory that defaults to the current directory, an iterable of
  `exclude` glob patterns naming packages to exclude, and an iterable of `include`
  glob patterns that, when given, override the default of including all packages.
- It returns the discovered package names, including PEP 420 implicit namespace
  packages (directories without an `__init__.py`).
