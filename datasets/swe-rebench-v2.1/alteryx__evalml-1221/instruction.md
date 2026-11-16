Add validation column to `rankings` and `full_rankings` computed from 1st CV fold
Add a `validation_score` column to `AutoMLSearch.rankings` and `AutoMLSearch.full_rankings` where the `validation_score` is computed from the 1st CV fold. Note: Don't calculate twice - take from first cv fold.

### Additional contract requirements

- Each entry in `AutoMLSearch.results['pipeline_results']` must also include a `validation_score` field equal to the score of the first CV fold.
- In both `rankings` and `full_rankings`, the columns must be ordered as `id`, `pipeline_name`, `score`, `validation_score`, `percent_better_than_baseline`, `high_variance_cv`, `parameters`.
