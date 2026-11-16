`UnleashClient().get_variant()` returns the same result when the feature is disabled vs enabled and there are no variants defined
**Is your feature request related to a problem? Please describe.**
It's unclear how to differentiate two cases:
- when the feature is enabled, but there are no variants defined for the feature and for the activated strategy
- when the feature is disabled

In both cases `DISABLED_VARIATION` is returned (`{"name": "disabled", "enabled": False}`).

**Describe the solution you'd like**
Could include "is_feature_enabled" field in the return value of `UnleashClient().get_variant()` and `Feature().get_variant()`

**Describe alternatives you've considered**
Now we either have to be aware if there are variants for a specific feature (and also for an activated strategy) or not or call both
`UnleashClient().get_variant()` and `UnleashClient().is_enabled()`, but that messes up the counting.

**Additional context**
Seems that in versions before 5.8.0 the result used to be `{"name": "disabled", "enabled": True}` if the feature is _enabled_ but there is no variant.
