Decide whether the consumer can update ConsumerRedistributeFrac
Currently, `ConsumerRedistributeFrac`, i.e., the fraction of tokens allocated to the consumer redistribution address during distribution events, which means it could be modified by the consumer through governance. I'd argue that the consumer should not be able to change this parameter without the consent of the provider chain. Thus, for now, we should add this as a field of the `CreateChildChainProposal`. Later we could allow this to be change by submitting a TX to the provider or through an IBC packet.

After discussions, the preferred solution is to keep the `ConsumerRedistributeFrac` hardcoded in the consumer chain. As a result, the validators on the provider chain can check the value when auditing the consumer binary, and the consumer chain cannot update it through governance.

### Additional contract requirements

- The consumer `Params` type must not contain a `ConsumerRedistributeFrac` field, and `NewParams` must not accept a redistribution-fraction argument.
- The redistribution fraction must not be a governance-updatable consumer parameter: the consumer param subspace must not register a `ConsumerRedistributeFrac` key, so a governance parameter-change proposal targeting it cannot succeed.
- During a distribution event the consumer sends 75% of its fee pool (rounded down to whole tokens) to the consumer redistribution module account and transmits the remaining tokens to the provider fee pool. This split is fixed and does not depend on any parameter.
