Twine uploads with `provides_extras` field, not `provides_extra`
### Is there an existing issue for this?

- [X] I have searched the existing issues (open and closed), and could not find an existing issue

### What keywords did you use to search existing issues?

provides_extra, provides_extras

### What operating system are you using?

Other

### If you selected 'Other', describe your Operating System here

_No response_

### What version of Python are you running?

```console
$ python --version
Python 3.11.8
```


### How did you install twine? Did you use your operating system's package manager or pip or something else?

```console
$ python -m pip install twine
```


### What version of twine do you have installed (include the complete output)

```console
$ twine --version
twine version 5.0.0 (importlib-metadata: 7.0.1, keyring: 24.3.0, pkginfo: 1.10.0, requests: 2.31.0, requests-toolbelt: 1.0.0, urllib3: 2.1.0)
```


### Which package repository are you using?

PyPI

### Please describe the issue that you are experiencing

Twine does not correctly `POST` the `Provides-Extra` field when it is present in package metadata.

### Please list the steps required to reproduce this behaviour

1. Build a package with [`Provides-Extra`](https://packaging.python.org/en/latest/specifications/core-metadata/#provides-extra-multiple-use) metadata field ([example](https://files.pythonhosted.org/packages/57/90/4bcbd9d539d1b92cf38accb9e910ffa770ea4d28e7b4afce3b398f79cae6/pyroblack-2.3.48-py3-none-any.whl));
2. Upload it with `twine`;
3. Observe that twine `POST`s the field `provides_extras`, and not `provides_extra`;
4. Observe that PyPI does not record the `Provides-Extra` values.

### Anything else you'd like to mention?

I introduced this bug [six years ago](https://github.com/pypa/twine/commit/7369e6219af6b61c82bfb68afac57250f5664577), so my apologies 🙂.
