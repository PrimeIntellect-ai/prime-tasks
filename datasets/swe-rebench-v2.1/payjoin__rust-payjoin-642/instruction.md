NS1R proposal builder should not accept duplicate proposal
> This is working as expected but I do wonder if contexts here should be len == 1. Since both the hpke context and the proposal is the same it would make sense to me that  `UncheckedProposalBuilder.add()` would disallow the caller to add duplicate sessions. I still think the ns1r session would succeed bc only one PSBT ends up on the directory for this hpke session but it still seems wrong and error prone. This is outside the scope of this PR.

_Originally posted by @0xBEEFCAF3 in https://github.com/payjoin/rust-payjoin/pull/632#discussion_r2037346020_

### Additional contract requirements

When adding a proposal, the multiparty proposal builder must reject it if its HPKE session is already represented in the builder. The rejection may use any error type or message.
