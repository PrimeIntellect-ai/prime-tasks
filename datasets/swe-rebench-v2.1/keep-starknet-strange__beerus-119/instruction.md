feat: `l1ToL2MessageNonce`
# Feature Request

**Describe the Feature Request**

As a user, I would like to query `l1ToL2MessageNonce` of the `StarkNetCore` contract.

**Describe Preferred Solution**

`l1ToL2MessageNonce` is accessible in the core library, and as a CLI command, and a REST API endpoint.

**Describe Alternatives**

<!-- A clear and concise description of any alternative solutions or features you've considered. -->

**Related Code**

<!-- If you are able to illustrate the bug or feature request with an example, please provide it here. -->
- `beerus_core`
- `beerus_cli`
- `beerus_rest_api`

- [X] Yes
- [ ] No

### Additional contract requirements

- The CLI query is available as `beerus starknet l1-to-l2-message-nonce`.
- The REST API exposes the query with `GET /starknet/messaging/l1_to_l2_message_nonce`; a successful response includes the queried nonce as a JSON value.
- The core library exposes the query as the method `starknet_l1_to_l2_message_nonce` on `BeerusLightClient`, returning the nonce as a `U256`.
