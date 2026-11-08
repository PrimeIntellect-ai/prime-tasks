Public method to evaluate all the preprocessing steps of a pipeline
We currently define `PipelineBase._transform`--let's make that public so its easy for users to get the data which is passed to the estimator. And of course we should also add good test coverage to ensure the column names are set correctly, all the features are computed as expected.

An initial idea for a name: `compute_estimator_features`

Sidenote, once we add this, it'll be another thing we should think about as part of the DAG project #273

### Additional contract requirements

- The public method is `PipelineBase.compute_estimator_features(self, X)` in `evalml/pipelines/pipeline_base.py`.
- It returns a `pd.DataFrame` containing the result of applying every preprocessing component of the pipeline, excluding the final estimator. Its columns are named for the features produced by preprocessing; when preprocessing changes or expands the feature set, the returned names correspond to those transformed features rather than necessarily matching the input columns.
- If `X` is not a `pd.DataFrame`, it is converted to one.
