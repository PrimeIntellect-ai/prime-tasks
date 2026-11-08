[BUG] v0 fails for bad mapping but not v1
### CloudFormation Lint Version

cfn-lint 1.8.2

### What operating system are you using?

Mac

### Describe the bug

Create a CFT like

```
Mappings:
  qa:
    global:
      global:
      subnet: abc123
```

cfn-lint v0 fails for `E7001     Mapping qa has invalid property at global`
cfn-lint v1 passes


### Expected behavior

V1 should fail like V0 did

### Reproduction template


```
Mappings:
  qa:
    global:
      global:
      subnet: abc123
```

### Additional contract requirements

- For the reproduced malformed mapping, cfn-lint v1 must reject the mapping with an E7001 diagnostic identifying `global` as the invalid property in mapping `qa`.
