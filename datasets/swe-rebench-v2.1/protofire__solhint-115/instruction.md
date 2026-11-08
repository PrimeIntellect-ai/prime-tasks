mark-callable-contracts rule is firing a false positive on structs
The `mark-callable-contracts` rule is being triggered against `structs`, as they are instantiated very similarly to contracts. We should update this rule so that it does not get triggered by structs. Take for instance this example:

```sol
contract ReservePool {

  struct Token {
    address tokenAddress;
    string tokenSymbol;
    uint256 currentRate;
  }

  mapping(address => Token) public acceptedTokens;
.
.
.
  function addAcceptedToken(string memory tokenSymbol, address tokenAddress, uint256 rate) public onlyAdmins {
    // solhint-disable-next-line mark-callable-contracts, solhint is confusing structs for contracts
    Token memory token = Token({ tokenAddress: tokenAddress, tokenSymbol: tokenSymbol, currentRate: rate });
    acceptedTokens[tokenAddress] = token;
  }
.
.
.
}
```

Note that `solhint-disable-next-line` had to be used for this to pass solhint as the `struct` was being confused for a contract.
