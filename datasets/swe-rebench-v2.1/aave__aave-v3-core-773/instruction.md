The update of interest rates does not account for the real unbacked amount (can be bypassed if cap is 0)
If there is `unbacked` liquidity in the system and governance decides to "switch off" portals (setting a zero `unbackedMintCap`), the calculation of the interest rates would be wrong since this function would pass 0 as `unbacked` because of 0 `unbackedMintCap` (when we could have non-zero `unbacked`).

https://github.com/aave/aave-v3-core/blob/f3e037b3638e3b7c98f0c09c56c5efde54f7c5d2/contracts/protocol/libraries/logic/ReserveLogic.sol#L167-L198


Additionally, there is no check of the current `unbacked` amount in `IPoolConfigurator.setUnbackedMintCap`.

https://github.com/aave/aave-v3-core/blob/32f0e72bafdb5a29e5da5fdbd3539167964083a6/contracts/protocol/pool/PoolConfigurator.sol#L416-L426

### Additional contract requirements

A reserve may have outstanding unbacked liquidity when its unbacked mint cap is set to zero. This disables additional unbacked minting but does not erase the outstanding amount or make it zero for interest-rate calculations; a subsequent reserve update must calculate rates using the actual outstanding amount.
