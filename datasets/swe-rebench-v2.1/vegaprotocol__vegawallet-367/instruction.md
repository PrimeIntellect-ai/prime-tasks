Implement a new subcommand to sign a KeyRotate transaction
The validator will need to sign a transaction to be send to the network when they want their key to be rotated

This will need to be a special subcommand, which instead of sending the transaction straight to the network (we expect the master key to be held on a computer without access to internet), will just output a raw transaction.

Once the transaction is signed, it can be used with a wallet connected to the internet, to be sent to the vega network.

### Tasks
- [ ] Add a new subcommand to sign the KeyRotateCommand payload with a new validator key
- [ ] This subcommand should just output the transaction in protobuf bytes, encoded in base64

### Additional contract requirements

- The operation is exposed as the `rotate` subcommand of the `key` command, i.e. `vegawallet key rotate`. It accepts the existing `--wallet` and `--passphrase-file` flags, plus `--pubkey` (the new validator public key to rotate to), `--tx-height` (the block height at which the transaction is built) and `--target-height` (the block height at which the key change takes effect).
- The command signs the transaction with the wallet's master key. The printed transaction must be a serialized protobuf transaction, encoded in base64, whose signature verifies against the master public key.
- The transaction's inner key-rotation command carries the target block height and identifies the new public key by its hash.
- The command must not send anything to the configured network; it only prints the signed transaction.
