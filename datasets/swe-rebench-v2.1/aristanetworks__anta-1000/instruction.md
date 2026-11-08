Silent exits when providing invalid inventory or catalog files
When providing an invalid inventory or catalog file in ANTA CLI, the program exits silently without any error messages or exceptions.

This can be reproduced with:

1. An invalid inventory file:
```yaml
anta_inventory:
  - host: 172.20.20.101
    name: DC1-SPINE1
    tags: ["SPINE", "DC1"]
```
2. Or an invalid catalog file:
```yaml
- anta.tests.aaa:
  - VerifyTacacsSourceIntf:
      intf: Management0
      vrf: default
      filters:
        tags: ["BL"]
```

Suggested fix is to improve exception handling in:
- https://github.com/aristanetworks/anta/blob/v1.2.0/anta/cli/utils.py#L246
- https://github.com/aristanetworks/anta/blob/v1.2.0/anta/cli/utils.py#L323

### Additional contract requirements

- When parsing an invalid inventory, log a CRITICAL-level message containing `Failed to parse the inventory`. When parsing an invalid catalog, log a CRITICAL-level message containing `Failed to parse the catalog`.
