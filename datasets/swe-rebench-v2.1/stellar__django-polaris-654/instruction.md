watch_transactions: support fee-bump transactions
### What problem does your feature solve?

If a wallet or SEP-31 sender uses fee-bump transactions to initiate a withdrawal or remittance, Polaris' `watch_transactions` transaction streamer will fail to deserialize it.

### What would you like to see?

We need to add support for streaming these fee-bump transactions.
