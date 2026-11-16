Support scripts properly
See https://packaging.python.org/en/latest/specifications/binary-distribution-format/#recommended-installer-features & https://github.com/mesonbuild/meson-python/issues/220. We should process scripts in `/scripts` to replace a nice shebang with the required one.

This is what setuptools uses (and misses pypy):

[HIDDEN]

Also seems to not suppert `pythonw`. Though I'm not sure you'd indicate that in a source file that you wanted to run on Linux too.

### Additional contract requirements

During wheel construction, ordinary Python shebangs in scripts installed under `/scripts` must be rewritten to the wheel-required `#!python` form. PyPy interpreter shebangs must also be recognized and rewritten. Preserve any optional trailing arguments from a recognized shebang, and retain the remainder of each script unchanged.
