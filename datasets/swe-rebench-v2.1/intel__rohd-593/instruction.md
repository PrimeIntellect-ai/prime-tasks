"Default" values for `FiniteStateMachine`s
### Motivation

Often there is a "default" value that would be desirable for most states in a `FiniteStateMachine`, but the current implementation requires repeating the same default across all states in order to avoid an inferred latch.

### Desired solution

Upgrade the `FiniteStateMachine` API to support some way to add defaults.

[HIDDEN]

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

- The single-clock constructor `FiniteStateMachine(clk, reset, resetState, states, {asyncReset, setupActions})` and the multi-clock constructor `FiniteStateMachine.multi(clks, reset, resetState, states, {asyncReset, setupActions})` must both accept a `setupActions` argument: a list of conditional actions that are applied before any state-specific actions, so that signals default to those values in every state unless a state overrides them.
- `FiniteStateMachine` must expose a public `setupActions` list containing the default actions supplied to it.
