SMO should use internal balance if context is internal
> This should subtract from a contract balance if the context is internal. Although this should be done in a separate PR.

_Originally posted by @Voxelot in https://github.com/FuelLabs/fuel-vm/pull/354#discussion_r1121093658_

### Additional contract requirements

When SMO executes in an internal context, it debits the sending contract's base-asset balance by the amount sent. In a non-internal context, SMO continues to debit the external balance pool.
