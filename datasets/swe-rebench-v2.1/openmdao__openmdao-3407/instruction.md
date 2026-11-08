Change language in the 'check unconnected inputs' config  check to avoid confusion.
### Description

Currently the config check says that 'the following inputs are not connected', but it should really say that 'the following inputs are connected to _auto_ivc variables' because there are no unconnected inputs any more.

### Example

The current `test_check_config.py:TestCheckConfig.test_unconnected_auto_ivc` test demonstrates the current behavior.

### OpenMDAO Version

3.34.3

### Relevant environment information

_No response_

### Additional contract requirements

- The warning message must use this exact heading: `The following inputs are connected to Auto IVC output variables:\n`.
