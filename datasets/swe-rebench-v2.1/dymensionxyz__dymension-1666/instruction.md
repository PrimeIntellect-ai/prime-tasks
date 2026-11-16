Data Correction Request: denom metadata of existing GAMM on mainnet
The existing GAMM pools on mainnet, have denom metadata not satisfy validate basic (already fixed in 3D), so please correct them during migration.

### Additional contract requirements

- After the v4 upgrade has run, the denom metadata stored for each of the existing mainnet GAMM pool share denoms `gamm/pool/1` through `gamm/pool/13` must pass the basic metadata validation (`Metadata.Validate`) of the bank module.
- The correction must keep the base denom of each of these metadata entries unchanged.
