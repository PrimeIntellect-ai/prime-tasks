[Oxford2] Update local forger to include 'whitelist' property for smart rollup originate
Oxford2 introduced changes to Smart Rollups where you can now make use of private rollups.

The whitelist property is introduced as an optional property now in `smart_rollup_originate`

Investigate and implement the changes in local forger to reflect the changes.

> The smart_rollup_originate operation now also takes an optional whitelist of public key hashes. This whitelist cannot be used yet (the sc_rollup.private_enable flag has to be set to true). (MR [!9401](https://gitlab.com/tezos/tezos/-/merge_requests/9401))

Relevant docs:
- https://tezos.gitlab.io/protocols/018_oxford.html#smart-rollups
