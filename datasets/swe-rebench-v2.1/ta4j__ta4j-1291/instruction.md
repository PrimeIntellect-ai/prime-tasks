[BUG] VolumeBarBuilder and TickBarBuilder: aggregate all cumulative fields
**Describe the bug**
The `VolumeBarBuilder` aggregates by `volume` and correctly creates a new bar after `volumeThreshold` is reached. However, while sampling, it should also aggregate its `amount` and `trades`. The same applies to the `TickBarBuilder`.

Instead

https://github.com/ta4j/ta4j/blob/a5eb46ffdfcfa78a11906bb3d66b509c4918b421/ta4j-core/src/main/java/org/ta4j/core/bars/VolumeBarBuilder.java#L186

[HIDDEN]

**Expected behavior**
Cumulative fields (volume, amount, trades) should always be aggregated while sampling.

### Additional contract requirements

- For `VolumeBarBuilder` and `TickBarBuilder`, when a completed bar has no amount supplied by any of its samples, the bar's amount must be computed as the bar's close price multiplied by the bar's volume.
- For both builders, amounts supplied by multiple samples in the same bar must be added together; a later sample's amount must not replace an earlier sample's amount.
