Revert withdraw functionality
Want to remove this feature until it has been audited. This release should only have random minting and a few other minor updates.

### Additional contract requirements

- For each successful non-admin mint, transfer UNIT_PRICE - MINT_FEE in NATIVE_DENOM directly to the minter creator, leaving no mint proceeds in the minter contract.
