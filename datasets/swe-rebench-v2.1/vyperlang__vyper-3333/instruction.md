Add missing PC Maps to `vyper_json` output
### Version Information

* vyper Version (output of `vyper --version`): 0.3.7
* OS: macOS
* Python Version (output of `python --version`): 3.9.13

### What's your issue about?

The following PC Maps are missing from `vyper_json` output, with `"outputSelection": "*"`:

* `breakpoints`
* `error_map`
* `pc_breakpoint`
* `pc_pos_map`

### How can it be fixed?

Fill this in if you know how to fix it.

### Additional contract requirements

With `"outputSelection": "*"`, the `vyper_json` output for each contract must include the full source map under `evm.deployedBytecode.sourceMapFull`. This field contains the PC maps listed above.
