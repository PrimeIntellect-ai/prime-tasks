Locked state of contracts return consistent response
## Overview
When contracts are in `locked` state, they should return that information in a consistent way for all contracts.

## Currently
`external-staking` contract returns an error on undelegate msg:
```
smart query error (ignored): rpc error: code = Unknown desc = Value is already write locked: query wasm contract failed: unknown request
```

While it on `delegate` it returns query response of `locked: {}`. Which is more consistent.

## Proposal
If contract is is locked state, it should not return an error, but a response of `locked: {}`.

### Additional contract requirements

- Add a public enum `MaybeStake` in `contracts/provider/external-staking/src/msg.rs` with variants `Stake(Stake)` and `Locked {}`, and a method `MaybeStake::unwrap(self) -> Stake` that returns the inner `Stake` for the `Stake` variant.
- The external-staking stake query for a user and validator returns `MaybeStake`.
- `StakeInfo` in `contracts/provider/external-staking/src/msg.rs` has fields `owner: String`, `validator: String` and `stake: MaybeStake`, and a constructor `StakeInfo::new(owner: &str, validator: &str, stake: &Stake) -> StakeInfo` that sets `stake` to `MaybeStake::Stake(stake.clone())`.
- Add a public function `Stake::from_amount(amount: Uint128) -> Stake` in `contracts/provider/external-staking/src/state.rs` that returns a `Stake` with its `stake` field set to `amount` and the remaining fields at their defaults.
- Add a public enum `MaybeLienResponse` in `contracts/provider/vault/src/msg.rs` with variants `Lien { lienholder: String, amount: Uint128 }` and `Locked {}`.
- The vault account-claims query returns a list of `MaybeLienResponse` values.
