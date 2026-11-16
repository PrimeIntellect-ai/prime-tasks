feat: Starknet RPC "get_class" call
# Description

Implement "get_class" Starknet RPC call

Starknet-RS Implementation
https://github.com/xJonathanLEI/starknet-rs/blob/da72d0130eb48cc84288c9948d983f5f78cf6054/starknet-providers/src/jsonrpc/mod.rs#L227

# Acceptance Criteria

- Beerus can query a Starknet's block number
- Associated cli command
- Associated rest api wrapper
- Helios integration
- Units tests
- Integration tests

### Additional contract requirements

- Add a method `get_class(&self, block_id: &BlockId, class_hash: FieldElement) -> Result<ContractClass>` to the `StarkNetLightClient` trait in `beerus_core::lightclient::starknet`. It returns the contract class definition for the given block identifier and class hash, and propagates the underlying error message unchanged.
- Add a public helper `create_mock_contract_class() -> (ContractClass, serde_json::Value)` in module `beerus_core::starknet_helper` that returns a contract class and its JSON representation.
- Add a CLI sub-command variant `StarkNetSubCommands::QueryGetClass { block_id_type: String, block_id: String, class_hash: String }` in `beerus_cli::model`, together with a response variant `CommandResponse::StarknetQueryGetClass(ContractClass)`.
- The CLI `get_class` flow parses the block identifier and class hash from their string arguments and propagates the underlying error message unchanged.
- Add a REST endpoint `GET /starknet/contract/class/<class_hash>?block_id=<block_id>&block_id_type=<block_id_type>` that returns a JSON object with `abi`, `entry_points_by_type` and a base64-encoded `program`.
- When the backend returns an error, the REST endpoint responds with HTTP 500 and a JSON body `{"error_message":"<original error message>"}`.
