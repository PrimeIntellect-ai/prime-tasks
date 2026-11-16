Implement `ErrorOutOfGasAccountAccess` state error
### Descirption
For opcodes BALANCE, EXTCODESIZE, EXTCODEHASH, which possibly touches an extra account

### Circuit
https://github.com/privacy-scaling-explorations/zkevm-circuits/issues/1349

### Additional contract requirements

For these opcodes, determine the account-access gas cost from whether the target account is warm: the cost is 100 gas when warm and 2600 gas when cold. This error applies when the current gas left is less than the applicable cost. The current call must be marked unsuccessful. A root call transitions to `EndTx`; a non-root call restores the caller's context and consumes the failing call's remaining gas. The RW-counter accounting for the error must include the current call's reversible-write counter: the end-of-reversion RW counter is the end-of-step RW counter plus that counter.
