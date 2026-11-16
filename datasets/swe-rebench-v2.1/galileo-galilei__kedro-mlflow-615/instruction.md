Using MLFlow>=2.18.0 with ThreadRunner creates several runs
<!-- **_If you like the repo, please give it a :star:_** -->

## Description
Updating to MLFlow 2.18.0 makes kedro-mlflow's datasets create and log to different runs (new run per artifact). It also breaks kedro-mlflow's test suite.

## Context
Cannot use MLFlow >= 2.18

## Steps to Reproduce

1. Log artifact(s) with any kedro-mlflow's dataset

## Expected Result

Artifact should be logged to the initial run

## Actual Result

Artifact is logged to a new run


Test suite failing on 2.18
```
===short test summary info ===
FAILED tests/mlflow/test_kedro_pipeline_model.py::test_kedro_pipeline_model_save_and_load[pipeline_inference_with_parameters-catalog_with_parameters-data-result3] - mlflow.exceptions.MlflowException: The provided MLFLOW_EXPERIMENT_ID environment variable value `514828615563594097` does not exist in the tracking server. Provide a valid experiment_id.
...

78 failed, 165 passed, 2 skipped, 1 xfailed, 41 warnings in 74.11s (0:01:14)
```

Initial run and subsequent runs with artifacts logged

<img width="1102" alt="image" src="https://github.com/user-attachments/assets/708556ca-b228-4a5d-aa9e-a544a4ecac6c">


## Your Environment

<!-- Include as many relevant details about the environment in which you experienced the bug: -->

* `kedro` and `kedro-mlflow` version used (`pip show kedro` and `pip show kedro-mlflow`): 0.19.8 and 0.13.3
* Python version used (`python -V`): 3.10.14
* Operating system and version: MacOS M2 15.1.1

## Does the bug also happen with the last version on master?

Yes
<!-- The plugin is still in early development and known bugs are fixed as soon as we can. If you are lucky, your bug is already fixed on the `master` branch which is the most up to date. This branch contains our more recent development unpublished on PyPI yet.

In your environment, please try:

```bash
pip install --upgrade git+https://github.com/Galileo-Galilei/kedro-mlflow
```

And check if you can to reproduce the error. If you can't, just wait for the next release or use the master branch at your own risk! -->

### Additional contract requirements

- After `MlflowHook.before_pipeline_run` starts a run, the catalog's `MlflowArtifactDataset` must have a `run_id` attribute equal to that run's ID.
- With MLflow 2.18 or later, when a pipeline runs with `ThreadRunner`, every artifact logged through a Kedro-MLflow dataset must be associated with the initial run rather than a separate run.
