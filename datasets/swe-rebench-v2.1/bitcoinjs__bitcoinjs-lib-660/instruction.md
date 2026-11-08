s/hashType/hashTypes in `TransactionBuilder.inputs`
Reference https://github.com/bitcoinjs/bitcoinjs-lib/issues/417.

We currently assume that signatures are signing with the same hash type, but as described by @dthorpe,  that assumption can break in some scenarios:

(paraphrased and simplified)
```
* Alice and Bob send funds to a 2-of-2 multisig
* Bob builds a transaction spending the funds, and sends it to Alice
* Alice signs the relevant inputs with SIGHASH_ALL | SIGHASH_ANYONECANPAY and returns the transaction
* Carol adds some (signed) inputs to the transaction
* Bob signs the transaction with SIGHASH_ALL
* Transaction is broadcasted
```
