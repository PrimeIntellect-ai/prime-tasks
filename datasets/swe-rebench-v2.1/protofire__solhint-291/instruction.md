`compiler-version` should ignore `pragma experimental` statements
File:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

contract Main {
}
```

Config:

```
{
  rules: { 'compiler-version': ['error', '^0.7.4'] }
}
```

This throws an error in the second pragma, which is obviously wrong. The fix is probably to check here:

[HIDDEN]

that [HIDDEN]

### Additional contract requirements

The compiler-version rule must continue to report an error when a Solidity version pragma does not satisfy the configured semver requirement.
