Unify redundant power-accounting methods
The power actor contains a number of methods that essentially just update the power table:
- OnSectorProveCommit
- OnSectorTerminate
- OnFaultBegin
- OnFaultEnd
- OnSectorModifyWeightDesc

The only differences between these are whether the power is added or removed, and including calculation of pledge collateral.

The collateral calculation in OnSectorModifyWeightDesc is unused and can be removed. This means that all but the first of these methods can be combined into an `UpdateClaimedPower` method (c.f. `UpdatePledgeTotal`).

Then `OnSectorProveCommit` can possibly be combined if pledge calculation can be moved to the miner actor (see #468, #476)

### Additional contract requirements

- The power actor exposes a method `UpdateClaimedPower(rt Runtime, params *UpdateClaimedPowerParams) *adt.EmptyValue`, exported as `builtin.MethodsPower.UpdateClaimedPower`.
- `UpdateClaimedPowerParams` is a public struct with fields `RawByteDelta abi.StoragePower` and `QualityAdjustedDelta abi.StoragePower`.
- `UpdateClaimedPower` may only be invoked by a miner actor; a call from any other actor type is rejected.
- `UpdateClaimedPower` applies both deltas to the calling miner's claimed power. Either delta may be positive or negative; no additional restriction is placed on their signs.


- - A non-miner caller must be rejected with `exitcode.ErrForbidden`.
- On success, `UpdateClaimedPower` must return `nil`.
