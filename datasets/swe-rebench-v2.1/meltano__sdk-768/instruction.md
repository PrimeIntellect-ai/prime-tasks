feature: Validate tap/target config options
I just found that I've been running a tap with a misnamed option in the config file for almost 3 months. Despite this fact, `name=tap-github level=INFO message=Config validation passed with 0 warnings.`
It would be helpful if the sdk, as part of the config validation, actually raised an error when encountering unexpected options. For instance, `mypy` has an [option](https://mypy.readthedocs.io/en/stable/command_line.html#cmdoption-mypy-warn-unused-configs) for this, which is very helpful to catch typos in config and such.

The following test clarifies the bug (inserted in `tests/core/test_plugin_config.py`):

```python
SAMPLE_CONFIG_WITH_ADDITIONAL_OPTION: Dict[str, Any] = {
    "default_true": False,
    "option_not_in_schema": 1,
}
def test_tap_config_validation_fails_on_invalid_option():
    """Verify that config validation fails on invalid option."""
    with pytest.raises(ValidationError):
        TapConfigTest(
            config=SAMPLE_CONFIG_WITH_ADDITIONAL_OPTION, parse_env_config=True
        )
    # this test fails because ValidationError is not raised
```

### Additional contract requirements

- `validate_config` defaults to `True` for `Tap`, `StreamTransform`, and `SQLiteTarget`. Therefore the construction shown above (`TapConfigTest(config=SAMPLE_CONFIG_WITH_ADDITIONAL_OPTION, parse_env_config=True)`) raises a `ConfigValidationError` even though `validate_config=True` is not passed explicitly.
