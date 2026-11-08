`wallet cardinals` should not return runic utxos
As of right now `ord wallet cardinals` returns runic utxos.

This is an unexpected behaviour, as spending those utxos results in spent rune balances.

`wallet cardinals` should return only common non-rune, non-inscription utxos
