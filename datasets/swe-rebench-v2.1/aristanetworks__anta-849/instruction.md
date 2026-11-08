Add the test case to verify SNMP Logging Configuration.
This test case verifies whether SNMP logging is enabled and if the SNMP host and VRF are correctly configured

### Additional contract requirements

- Add a public class `VerifySnmpHostLogging` in module `anta.tests.snmp` that accepts a `hosts` input: a list of SNMP hosts to verify. For each host it verifies that SNMP logging is enabled and that the host's VRF matches the expected value.
- Add a public Pydantic model `SnmpHost` in module `anta.input_models.snmp` with:
  - `hostname`: an IPv4 address (`IPv4Address`) or a hostname (`Hostname`) identifying the SNMP notification host.
  - `vrf`: an optional VRF name (`str`) that defaults to `"default"` when not supplied.
  - `__str__` returning the string `"Host: {hostname} VRF: {vrf}"`, used in failure messages to show the expected host and VRF.
