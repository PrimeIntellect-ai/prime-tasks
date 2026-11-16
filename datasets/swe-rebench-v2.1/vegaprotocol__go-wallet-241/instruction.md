Update protos to rename SubmitTransactionV2 into SubmitTransaction
Do what the title says.

### Additional contract requirements

- `NodeForward.SendTx` must forward the transaction to the node through the renamed `SubmitTransaction` RPC.
