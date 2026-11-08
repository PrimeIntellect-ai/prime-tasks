Support legacy formats for absent package metadata
Some packages lack [license](https://packaging.python.org/specifications/core-metadata/#license) and/or [classifiers](https://packaging.python.org/specifications/core-metadata/#id22) fields.
It seems that depending on the `setuptools version`, default values for missing [metadata]() fields may vary, so that it returned by PyPI API as:
- `""`, i.e. empty string (see [aio-throttle](https://pypi.org/project/aio-throttle/))
-  `"UNKNOWN"` (see [swagger-bundler](https://pypi.org/project/swagger-bundler/))
- `[]`
- `["UNKNOWN"]`

Let's consider all these as equivalent non-defined licenses to fall back to github repo license check.
