estimation: Return a list of skipped resources
## Abstract

Currently, only the resources that had been successfully estimated are returned. The user has no way of knowing which resources from the plan were skipped (due to e.g. not being supported).

The skipped resources should be returned alongside the estimated ones.

## Implementation details

This could be accomplished by including a `SkippedResources []string` field (or similar) in the `cost.State` struct, as well as having a helper method on the `cost.Plan` to extract them.

## Suggestions/ideas

Many Terraform resources are inherently free (such as from the `null` or `local` providers) and shouldn't be included as "skipped." One idea could be to have a list of free resources that should never be estimated and that should never be marked as "skipped." The other would be to ignore all unknown providers and mark as skipped only unsupported resources of supported providers.

### Additional contract requirements

`cost.Plan` must expose a `SkippedAddresses()` method that returns skipped resource addresses from both the prior and planned states. If the same address is skipped in both states, it appears only once in the returned list. Resources that are inherently free must not appear in the skipped-resource list. This includes resources belonging to the Terraform `null` and `local` providers, even when they are present in the plan.
