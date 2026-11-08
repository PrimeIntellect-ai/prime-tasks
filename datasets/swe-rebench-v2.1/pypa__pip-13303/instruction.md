Add support for Android
### What's the problem this feature will solve?

Android has been an [officially supported Python platform](https://peps.python.org/pep-0011/) since Python 3.13. More recently, its wheel tag format was added to the [PyPA specs page](https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/#android), and that format is now accepted by PyPI (e.g. see [here](https://pypi.org/project/pyspamsum/#files)).

pip should be able to install these wheels in two contexts:

* Directly on an Android device, e.g. via the Termux app.
* Through an app packaging tool such as Briefcase, using a command like `pip install --platform android_21_arm64_v8a mypackage`.

### Describe the solution you'd like

To avoid repeating the confusion around adding iOS support (#13053), I think the best sequence would be:

* Merge https://github.com/pypa/packaging/pull/880
* Make a `packaging` release.
* Update pip's vendored copy of `packaging`.
* Merge remaining changes to pip:
  * #13303

### Alternative Solutions

Briefcase and Chaquopy currently use a forked version of pip that's several years old. They therefore lack many of pip's recent features, such as the new resolver.

Termux and Kivy don't support Android wheels at all, and compile everything from source, which is much slower.

### Code of Conduct

- [x] I agree to follow the [PSF Code of Conduct](https://www.python.org/psf/conduct/).
