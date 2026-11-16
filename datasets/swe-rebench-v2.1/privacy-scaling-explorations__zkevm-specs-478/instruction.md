The InvalidCreationCode Error
### Describe the feature you would like

https://eips.ethereum.org/EIPS/eip-3541 required a new contract code that can not start by 0xef.

We need an error execution state in the circuit for this type of error.

### Additional context

I create this issue to keep track of the pull requests.

The markdown spec is worked in #478

### Additional contract requirements

- The invalid-creation-code error is represented in the circuit by the execution state `ExecutionState.ErrorInvalidCreationCode`.
- A RETURN executed by a CREATE or CREATE2 call whose returned code starts with the byte `0xEF` transitions to `ExecutionState.ErrorInvalidCreationCode`.
- A RETURN executed by a CREATE or CREATE2 call whose returned code does not start with the byte `0xEF` does not transition to `ExecutionState.ErrorInvalidCreationCode`.
