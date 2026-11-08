Support DAO initial balance in staked balance voting module.
The old contracts support allocating a token amount to the DAO on instantiation. We should support this in the `TokenInfo::New` variant.

### Additional contract requirements

- The instantiate message must expose an optional `initial_dao_balance: Option<Uint128>` field. When it contains a positive amount, the contract allocates that amount of the new token to the instantiating sender (the DAO).
