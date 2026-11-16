ios15 feature: relavance score
Please add support for relevance-score in push payload

### Additional contract requirements

The payload builder must provide `setRelevanceScore(Double relevanceScore)` to configure the notification's relevance score. When a score is set, the generated payload must include that same numeric value as `relevance-score` in its `aps` object.
