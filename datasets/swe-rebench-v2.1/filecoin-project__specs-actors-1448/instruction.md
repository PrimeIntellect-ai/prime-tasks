Miner.ProveCommitAggregate does not check sectors against abi.MaxSectorNumber
#### Description

`ProveCommitSector` checks the passed-in sector against `abi.MaxSectorNumber`:

https://github.com/filecoin-project/specs-actors/blob/a9f9f95f5e93bb7a27fd9fe8c0217e347fa1bef9/actors/builtin/miner/miner_actor.go#L975-L980

`ProveCommitAggregate` does not do this.

#### Recommendation

Add a check for consistency between the two methods. [HIDDEN]

https://github.com/filecoin-project/specs-actors/blob/a9f9f95f5e93bb7a27fd9fe8c0217e347fa1bef9/actors/builtin/miner/miner_state.go#L387-L392

### Additional contract requirements

- `ProveCommitAggregate` must reject submitted sector numbers greater than `abi.MaxSectorNumber`, consistent with `ProveCommitSector`.
