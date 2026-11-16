Functionality to delete wallets
**[Functionality to delete wallets vegaprotocol/token-frontend#302](https://vega-testnet.nolt.io/302)** by Mark Owen <hr/> Please could you implement command line functionality for vegawallet to delete or rename a wallet. This would be useful for many reasons, for example if a user creates a wallet without noting down the mnemonic for some reason, and then wishes to start over with the same/previous wallet name.

### Additional contract requirements

- The CLI provides a `delete` command that deletes the wallet named by the `--wallet` flag. The command also accepts a `--force` flag.
- The `cmd` package exposes a public type `DeleteWalletFlags` with fields `Wallet string` and `Force bool`, and a method `Validate() error`. `Validate` returns `flags.FlagMustBeSpecifiedError("wallet")` when `Wallet` is empty, and returns nil when `Wallet` is non-empty and the flag rules are satisfied.
