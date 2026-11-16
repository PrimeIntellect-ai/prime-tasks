recommendation in updator VPA should be removed when updateMode is changed back to Off

### Additional contract requirements

- When `tortoise.Spec.UpdateMode` is `Off`, the updater VPA's recommendation is cleared and represented as a non-nil empty recommendation: `Status.Recommendation` is `&vpav1.RecommendedPodResources{}`.
- When `tortoise.Spec.UpdateMode` is `Off`, the updater VPA's `Spec.UpdatePolicy` is set to `UpdateMode: Initial` with `MinReplicas` equal to one less than the replica count passed to the update (9 when the replica count is 10). This also holds when the input VPA has no recommendation.
