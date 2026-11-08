Low sensitivity of explicit-types
The explicit-type rule is not checked when casting a variable.

## Example

Option: `explicit`

```solidity
function test() external {
  uint256 a = uint(10);
}
```

Expected: error because of `uint(10)`

Observed: no errors
