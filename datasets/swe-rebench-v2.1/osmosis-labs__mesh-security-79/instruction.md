List of pending rewards per user in external staking
Bonus: it would be nice to have a list of all pending rewards for a user.

[HIDDEN]

Even without pagination, it would be very useful for any UI

_Originally posted by @ethanfrey in https://github.com/osmosis-labs/mesh-security/pull/46#discussion_r1217896481_

### Additional contract requirements

- Add a query `all_pending_rewards(user: String, start_after: Option<String>, limit: Option<u32>)` to the external staking contract. It returns `AllPendingRewards { rewards: Vec<ValidatorPendingReward> }`, listing the pending reward for the given user on every validator the user has staked on, ordered by validator address ascending. Validators the user never staked on are omitted.
- `start_after` is an optional validator address; when provided, only validators strictly after it in ascending address order are returned.
- `limit` is an optional maximum number of entries to return.
- Add a public struct `ValidatorPendingReward { validator: String, amount: Coin }` in `contracts/provider/external-staking/src/msg.rs`, together with a constructor `ValidatorPendingReward::new(validator: impl Into<String>, amount: u128, denom: impl Into<String>)` that sets `validator` to the given validator and `amount` to `coin(amount, denom)`.
