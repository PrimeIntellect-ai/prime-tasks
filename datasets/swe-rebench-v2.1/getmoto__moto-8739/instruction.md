setuptools deprecation warnings
When building the wheel for 5.1.2, I'm seeing the following deprecation warnings:

```
/usr/lib/python3.10/site-packages/setuptools/dist.py:759: SetuptoolsDeprecationWarning: License classifiers are deprecated.
!!

        ********************************************************************************
        Please consider removing the following classifiers in favor of a SPDX license expression:

        License :: OSI Approved :: Apache Software License

        See https://packaging.python.org/en/latest/guides/writing-pyproject-toml/#license for details.
        ********************************************************************************

!!
  self._finalize_license_expression()
```

### Additional contract requirements

- Building a wheel should not emit setuptools’ deprecated license-classifier warning.
