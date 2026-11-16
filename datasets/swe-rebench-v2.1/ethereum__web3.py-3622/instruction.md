Add support for `eth_simulateV1`
### What feature should we add?

The endpoint `eth_simulateV1` was [recently added to geth](https://github.com/ethereum/go-ethereum/pull/27720). This cna be quite useful for users of *web3.py*. We should add support for this new method.

### Additional contract requirements

- Add a public method `Eth.simulate_v1(payload, block_identifier)` on the `web3.eth` namespace. It sends an `eth_simulateV1` RPC request to the node and returns a sequence of simulation results.
- Add a public async method `AsyncEth.simulate_v1(payload, block_identifier)` that performs the same `eth_simulateV1` request and resolves to the same sequence of simulation results.
- `payload` is a mapping containing a `blockStateCalls` sequence. Each entry may contain `blockOverrides`, `stateOverrides`, and a `calls` sequence of transaction-like mappings. The payload may also contain `validation` and `traceTransfers` flags.
- `block_identifier` is a block number, block hash, or block tag such as `"latest"`.
- Each returned simulation result extends block data and contains a `calls` sequence. Each call result contains `returnData`, `logs`, `gasUsed`, and `status` (and optionally `error`).
