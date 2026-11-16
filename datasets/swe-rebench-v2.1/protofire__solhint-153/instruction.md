no-empty-blocks should not run on default-functions
When a default-function is used, its common to not do anything in the function itself.

```solidity
    function() public payable {
        // got money
    }
```

Solhint currently gives the warning `Code contains empty block  no-empty-blocks`.
