[MNT] Range-based AD metrics: The functions in `_continuous.py` need to be updated to use the new implementations
Once, #2781 is merged, we need to update the following metrics to also use the new implementation of the range-based precision and recall metrics:

- `f_score_at_k_ranges`
- `rp_rr_auc_score`

In file `aeon/benchmarking/metrics/anomaly_detection/_continuous.py`; Please also update the tests to not require the soft-dependency `prts` anymore.
