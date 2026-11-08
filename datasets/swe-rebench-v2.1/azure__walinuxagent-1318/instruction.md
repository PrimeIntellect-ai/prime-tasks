Record OS boot time for Failed Provisions Too
The OS boot time is recorded in the Provision event **only** in the case of a successful provision.  The OS boot time should be recorded in the case of a failed provision too.

### Additional contract requirements

- The provisioning event message emitted for a failed provision must begin with `Provisioning failed:` and end with a duration suffix formatted as `(<digits>.<digits>s)`, with at least one digit on each side of the decimal point (for example `Provisioning failed: [ProvisionError] --unit-test-- (1.23s)`).
- `ProvisionHandler.report_event(self, message, is_success=False)` in `azurelinuxagent/pa/provision/default.py` emits the provisioning event; for a failed provision the `is_success` flag is `False`.


- For a failed provision with error detail `[ProvisionError] --unit-test--`, the event message must have the form `Provisioning failed: [ProvisionError] --unit-test-- (<digits>.<digits>s)`, with at least one digit on each side of the decimal point.
