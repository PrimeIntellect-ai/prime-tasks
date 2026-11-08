Manual change of the contract response can still be executed successfully.
**Brief of the issue**
Describe here

**Your environment**
XuperUnion and OS/Go/gcc version etc.

**Repo steps**
step1
I can get the preexe_result through preexe function.
step2
And then,I change the response of the contract that there is the amount of utxoOutput.
step3
I make a new tx and  post into the net.
While it can be invoked successfully.

**Expected behaviours**
Describe what you expected to happen.
I think that it is not the contract result, it can not be successful.
**What actually happened**
Describe what actually happened. Include the full traceback if there was an exception.

**Additional information**
If possible, include a minimal, complete, and verifiable example to help us identify the issue. This also helps check that the issue is not with your own code.

### Additional contract requirements

- The contract UTXO declared in a transaction's transient write set must be validated before the transaction is executed. `XModel.PrepareEnv` (xmodel/env.go) must return a non-nil error when that declaration is ineffective. In particular, a transaction whose contract response was manually changed so that a declared contract output is absent from `tx.TxOutputs` or a declared contract input is absent from `tx.TxInputs` must be rejected by `PrepareEnv`.
