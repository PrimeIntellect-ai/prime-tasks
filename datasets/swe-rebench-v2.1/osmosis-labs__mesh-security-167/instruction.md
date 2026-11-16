Native-staking empty liens cleanup
Currently empty liens leave a zero entry in the liens map. Remove / cleanup empty liens as an improvement / for cleanup reasons.

### Additional contract requirements

- The vault contract exposes a `claim` query taking an account address and a lienholder address,  When no claim exists for the pair, the query fails with the error variant `ContractError::NoClaim`, whose message is `No claim found`.
