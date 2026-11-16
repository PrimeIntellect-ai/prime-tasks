compiler-version should reject files without versions
If `compiler-version` is enabled, then a file like

```solidity
contract Foo {}
```

shouldn't pass that rule because there's no pragma with the solidity version.
