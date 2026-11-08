Enum variants should all use `Name {}` form.
In the interest of being consistent and making enums easy to write out in the frontend we should use the `Name {}` form for all our enum variants. I messed some of these up while writing the `cw-govmod-single` and `cw-governance` contract.

Specifically, the `Admin` and `TokenInfo` enums both have fields that don't follow this format.

### Additional contract requirements

- The token-related enum intended by this request in `cw-govmod-single` is `DepositToken`. All its variants must use the `Name {}` form: `VotingModuleToken {}` and `Token { address: String }`.
