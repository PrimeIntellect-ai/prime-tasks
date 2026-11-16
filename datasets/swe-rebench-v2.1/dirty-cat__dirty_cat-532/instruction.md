AttributeError: 'SimilarityEncoder' object has no attribute '_compute_drop_idx'
<!--Provide a brief description of the bug.-->
Our tests fail. For instance: https://github.com/dirty-cat/dirty_cat/actions/runs/4429118982/jobs/7769148318?pr=530

This is due to the fact that the [HIDDEN]
See https://github.com/scikit-learn/scikit-learn/commit/d8a3089d3732bb0fac159f0133894babe2168ec8

### Additional contract requirements

- Fitting a `SimilarityEncoder` with default parameters must succeed on the installed scikit-learn version (1.2 or later) and must not raise an `AttributeError`. After fitting, `fit_transform` on a single categorical column returns one row per input row and one column per distinct category.
