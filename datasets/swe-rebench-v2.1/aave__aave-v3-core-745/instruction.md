3.0.1. SigmaP review. Not emit events on _transfer() when balanceIncrease == 0
### Context

Regarding https://github.com/aave/aave-v3-core/pull/701

https://github.com/aave/aave-v3-core/blob/84b900ce583eb8b1174357c05882e4a9f1854c38/contracts/protocol/tokenization/base/ScaledBalanceTokenBase.sol#L157-L158

When `balanceIncrease() == 0`, it probably doesn't make sense to emit the events, given that they are done for accounting consistency, not going against the ERC20 standard.
Additionally, it is not consistent to have different behaviour for sender and recipient

### Additional contract requirements

- When an aToken `transfer` or `transferFrom` is executed and an account's accrued balance increase is zero, no `Transfer` or `Mint` event is emitted for that account. This applies to the sender and to the recipient alike; an account whose balance increase is nonzero still gets its `Transfer` and `Mint` events.
