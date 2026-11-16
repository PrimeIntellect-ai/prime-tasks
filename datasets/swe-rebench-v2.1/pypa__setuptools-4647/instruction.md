build meta wheel does not respect metadata_directory per PEP-517
From https://www.python.org/dev/peps/pep-0517/#build-wheel:

> If the build frontend has previously called prepare_metadata_for_build_wheel and depends on the wheel resulting from this call to have metadata matching this earlier call, then it should provide the path to the created .dist-info directory as the metadata_directory argument.

https://github.com/pypa/setuptools/blob/master/setuptools/build_meta.py#L208 though ignores the passed in ``metadata_directory`` argument and goes to regenerate this information in the root of the project.

```python
    def build_wheel(self, wheel_directory, config_settings=None,
                    metadata_directory=None):
        [HIDDEN]
```

### Additional contract requirements

The `bdist_wheel` command must accept a `dist_info_dir` option naming a
pre-generated `.dist-info` directory whose contents are reused when building
the wheel.
