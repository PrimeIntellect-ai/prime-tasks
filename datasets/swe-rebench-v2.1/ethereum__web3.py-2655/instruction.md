Add new predefined block identifiers
### What was wrong?

There are [new predefined block identifiers](https://github.com/ethereum/execution-apis/blob/830fcd8768ef46353c8a0e3b8df85af421026a98/src/schemas/block.yaml#L97-L98), "finalized" and "safe" that should be added to the current {"latest", "pending", "earliest"} set.


### How can it be fixed?

[HIDDEN]

### Additional contract requirements

- When requests are sent through the eth-tester provider, the `safe` and `finalized` block tags are forwarded as named block references, not treated as numeric block values.
- Add a public function `parse_block_identifier(web3, block_identifier)` in module `web3.contract`.
- `parse_block_identifier` returns the predefined block identifiers `"latest"`, `"earliest"`, `"pending"`, `"safe"`, and `"finalized"` unchanged.
- For an integer `block_identifier`, `parse_block_identifier` returns the integer or its conversion via `parse_block_identifier_int`.
- For a `bytes` or hex-encoded block hash, `parse_block_identifier` returns the block number (an `int`) obtained from `web3.eth.get_block`.
