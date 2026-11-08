Default val set in `add_control` or `set_control_options` is not applied.
### Description

Specifying the option `val=...` in `add_control` or `set_control_options` has no impact in dymos 1.13.0.


### Example

The test case to see if default values are "sticking" is no longer being applied, because the function upon which it relies overrides default values for other tests.  Removing those set_xxx_val calls will expose the error.

### Dymos Version

3.13.1-dev

### Relevant environment information

_No response_
