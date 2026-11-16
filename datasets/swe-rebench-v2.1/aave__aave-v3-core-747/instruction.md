Collateral flag not disabled when collateral is fully liquidated (due to non-zero liquidationProtocolFee)
The `[HIDDEN]` function [HIDDEN] for setting to false the flag of `useAsCollateral`

```
    // If the collateral being liquidated is equal to the user balance,
    // we set the currency as not being used as collateral anymore
    [HIDDEN]
      userConfig.setUsingAsCollateral(collateralReserve.id, false);
      emit ReserveUsedAsCollateralDisabled(params.collateralAsset, params.user);
    }
```

Kudos to @GopherJ for this! https://github.com/aave/aave-v3-core/pull/740

### Additional contract requirements

- When liquidation fully removes a user's collateral, the asset must no longer be marked as being used as collateral, including when a nonzero liquidation protocol fee is charged.
