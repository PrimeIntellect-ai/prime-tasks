Rename output columns of `add_pairwise_comparison()`
**Update**:
We decided to append `relative_skill` and `scaled_relative_skill` to the name of the score that was used for pairwise comparisons. So for example, `wis` would become `wis_relative_skill` etc.

We only have a column with `scaled_relative_skill` if there is a baseline specified for pairwise comparisons


---
Currently, the output of `add_pairwise_comparison()` is a column called `relative_skill` and one `scaled_relative_skill`.

The problem with that is that
a) it's not entirely clear what the metric is that was used for pairwise comparisons
b) you can only run this once without overwriting results / having to rename the column.

We could therefore append the name of the metric to `relative_skill`, i.e. something like `relative_skill_wis`. This is a bit ugly, but otherwise seems a good idea.

Questions:
- [x] Q1: Should we append metric names?
- [x] Q2: Are we otherwise happy with `relative_skill` and `scaled_relative_skill`? Can we maybe find something more concise?

Note: this will affect `get_forecast_unit()`, which finds all columns that are not protected / are not a metric.

### Additional contract requirements

- The relative-skill column produced by `add_pairwise_comparison()` and returned by
  `pairwise_comparison()` is named by prefixing the score column used for the
  comparison: `<metric>_relative_skill` (for example `wis_relative_skill`,
  `crps_relative_skill`, `brier_score_relative_skill`, `ae_median_relative_skill`).
- When a baseline is supplied, an additional column `<metric>_scaled_relative_skill`
  is produced (for example `wis_scaled_relative_skill`). This column is not produced
  when no baseline is supplied.
- The generic columns `relative_skill` and `scaled_rel_skill` are no longer produced
  by `add_pairwise_comparison()`, `pairwise_comparison()` or `summarise_scores()`.
- Metric-specific relative-skill columns ending in `_relative_skill` are not treated
  as forecast-unit identifiers by `get_forecast_unit()`.
