Bug Report: NAPALM get_facts() incorrect os_version parsing on Nexus 9K with NXOS 10.3(5)
## Description
The NAPALM `get_facts()` method is not correctly parsing the os_version for Cisco Nexus switches running NXOS 10.3(5). Instead of returning the actual version number, it returns the literal string "version".

## Environment
- Device Model: Cisco Nexus9000 C93180YC-FX3 chassis
- NXOS Version: 10.3(5) [Maintenance Release]
- NAPALM Version: 5.0.0

## Current Behavior
`get_facts()` returns:
```python
{
    'uptime': 123456.0,
    'vendor': 'Cisco',
    'os_version': 'version',  # This is incorrect
    'serial_number': 'FAKESERIAL',
    'model': 'Nexus9000 C93180YC-FX3 Chassis',
    'hostname': 'SWITCH1',
    ...
}
```

## Expected Behavior
`get_facts()` should return:
```python
{
    ...
    'os_version': '10.3(5)',  # This is the expected value
    ...
}
```

## Raw Device Output
```
Cisco Nexus Operating System (NX-OS) Software
TAC support: http://www.cisco.com/tac
Copyright (C) 2002-2024, Cisco and/or its affiliates.
[...]
Software
  BIOS: version 01.09
  NXOS: version 10.3(5) [Maintenance Release]
  Host NXOS: version 10.3(5)
  BIOS compile time: 10/08/2023
  NXOS image file is: bootflash:///nxos64-cs.10.3.5.M.bin
  NXOS compile time: 4/30/2024 12:00:00 [05/08/2024 05:39:13]
  NXOS boot mode: LXC
```

## Steps to Reproduce
1. Connect to a Cisco Nexus switch running NXOS 10.3(5) using NAPALM
2. Call the `get_facts()` method
3. Observe that the 'os_version' field contains "version" instead of "10.3(5)"

## Additional Notes
- The issue appears to be in the regex parsing of the 'show version' output
- The version string includes "[Maintenance Release]" suffix which might be affecting the parsing
- This might affect other NXOS versions with similar output format

## Possible Fix Direction
The current regex pattern in the NX-OS driver may need to be updated to handle the version string format "X.X(X) [Maintenance Release]" correctly.
