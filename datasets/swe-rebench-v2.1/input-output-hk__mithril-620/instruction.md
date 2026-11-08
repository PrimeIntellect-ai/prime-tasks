Remove VerificationKey and Stake from individual signature
## Why
After the change of removing the merkle path from the individual signature, the protocol relies on the aggregator to have the full Merkle tree to aggregate correctly. Therefore, we don't need the individual signature to contain the public key and stake.

## What
Currently, the signature is defined as:

```
pub struct StmSig {
    pub sigma: Signature,
    pub pk: StmVerificationKey,
    pub stake: Stake,
    pub indexes: Vec<Index>,
    pub signer_index: Index,
}
```

and should be changed to:

[HIDDEN]

### Additional contract requirements

An individual `StmSig` carries `sigma`, `indexes`, and `signer_index`, and does not carry a verification key or stake.
