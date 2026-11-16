test_invalid_special_forms fails on Python 3.14.0b2
```
[typing_extensions (main)]$ git rev-parse @
fadc1edbcfd942074007875007870c1df6acd4d0
[typing_extensions (main)]$ python3.14 --version
Python 3.14.0b2
[typing_extensions (main)]$ tox -e py314
py314: recreate env because python changed python_preference=None->'system'
py314: remove tox env folder .../typing_extensions/.tox/py314
py314: venv> /usr/bin/uv venv -p cpython3.14 --allow-existing --python-preference system .../typing_extensions/.tox/py314
.pkg: recreate env because python changed version_info=[3, 12, 6, 'final', 0]->[3, 13, 3, 'final', 0] | python_preference=None->'system'
.pkg: remove tox env folder .../typing_extensions/.tox/.pkg
.pkg: venv> /usr/bin/uv venv -p /usr/bin/python3 --allow-existing --python-preference system .../typing_extensions/.tox/.pkg
.pkg: install_requires> /usr/bin/uv pip install 'flit_core<4,>=3.11'
.pkg: _optional_hooks> python /usr/lib/python3.13/site-packages/pyproject_api/_backend.py True flit_core.buildapi
.pkg: get_requires_for_build_sdist> python /usr/lib/python3.13/site-packages/pyproject_api/_backend.py True flit_core.buildapi
.pkg: build_sdist> python /usr/lib/python3.13/site-packages/pyproject_api/_backend.py True flit_core.buildapi
py314: install_package> /usr/bin/uv pip install --reinstall --no-deps typing-extensions@.../typing_extensions/.tox/.tmp/package/6/typing_extensions-4.14.0rc1.tar.gz
py314: commands[0] .../typing_extensions/src> python -m unittest discover
................................................................................................................................................................................s......................................................................................................................................................................F...............................................s.................................s..........................................s.s...ss.....ssss.....s............................s............
======================================================================
FAIL: test_invalid_special_forms (test_typing_extensions.TestEvaluateForwardRefs.test_invalid_special_forms)
----------------------------------------------------------------------
Traceback (most recent call last):
  File ".../typing_extensions/src/test_typing_extensions.py", line 9112, in test_invalid_special_forms
    with self.assertRaisesRegex(
         ~~~~~~~~~~~~~~~~~~~~~~^
        TypeError, r"Plain .*Protocol('>)? is not valid as type argument"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    ):
    ^
AssertionError: TypeError not raised

----------------------------------------------------------------------
Ran 532 tests in 0.141s

FAILED (failures=1, skipped=13)
py314: exit 1 (0.32 seconds) .../typing_extensions/src> python -m unittest discover pid=802355
.pkg: _exit> python /usr/lib/python3.13/site-packages/pyproject_api/_backend.py True flit_core.buildapi
  py314: FAIL code 1 (1.14=setup[0.82]+cmd[0.32] seconds)
  evaluation failed :( (1.19 seconds)
```

### Additional contract requirements

- `evaluate_forward_ref` must accept special forms as standalone forward references. When a forward reference names one of `Protocol`, `Final`, `ClassVar`, or `Generic`, `evaluate_forward_ref` returns the corresponding object (the same object found in the resolution namespace) instead of raising `TypeError`. This holds regardless of the `is_argument` and `is_class` flags on the `ForwardRef`.
