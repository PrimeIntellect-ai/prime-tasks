[FEATURE] `TimeGapSplit` with stride
In the current implementation of `TimeGapSplit` the argument `validation_duration` is used as stride as well.

This leads to the impossibility of having overlapping validation periods. What about the possibility of adding a stride parameter to indicate the time shift for the training period?

The concrete use case is as follows: I would like to validate a model that retrains every week but forecast for multiple weeks ahead.

Happy to give it a try in the next following days if there is interest in adding this feature.

### Additional contract requirements

The stride parameter is exposed as `stride_duration`. Its value must be positive; when omitted, the splitter uses the validation duration as the stride. A supplied stride determines the time shift between successive training periods even when the training duration is inferred from `n_splits`; it is independent of the validation duration, so validation periods may overlap.
