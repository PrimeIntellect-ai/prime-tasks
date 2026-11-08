validation tests for option_string should test the new ARGS_SPEC options
I think `test_validation.py` needs some minor updates to better test the new spec for args with `type: option_string` where `options` should be a set or a dict. Right now these probably pass by coincidence because they test on lists.

```
    def test_valid_option(self):
        """Validation: test that a string is a valid option."""
        from natcap.invest import validation
        self.assertEqual(None, validation.check_option_string(
            'foo', options=['foo', 'bar', 'Baz']))

    def test_invalid_option(self):
        """Validation: test when a string is not a valid option."""
        from natcap.invest import validation
        error_msg = validation.check_option_string(
            'FOO', options=['foo', 'bar', 'Baz'])
        self.assertTrue('must be one of' in error_msg)
```

### Additional contract requirements

When an empty set is supplied as the `options` for `option_string` validation, validation is disabled and any value is accepted. This supports choices that are populated dynamically.
