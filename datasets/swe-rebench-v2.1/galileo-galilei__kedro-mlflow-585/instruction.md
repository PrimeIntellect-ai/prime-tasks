PipelineML breaks on kedro-viz 9.2.0
## Description

PipelineML breaks on kedro-viz 9.2.0

## Context

The new kedro-viz 9.2.0 release heavily refactors graph generation for namespaced pipelines - https://github.com/kedro-org/kedro-viz/pull/1897. It now uses `only_nodes_with_namespace` and `__sub__` pipeline methods, but PipelineML doesn't have them implemented.

## Steps to Reproduce

1. Have a PipelineML specified in kedro project (by using `pipeline_ml_factory`)
2. Run kedro viz

## Expected Result

Kedro viz should run, and pipeline should display training nodes

## Actual Result

Kedro viz cannot run at all

```
  File "repo/venv/lib/python3.10/site-packages/kedro_viz/data_access/repositories/modular_pipelines.py", line 61, in populate_tree
    sub_pipeline = pipeline.only_nodes_with_namespace(modular_pipeline_id)
  File "repo/venv/lib/python3.10/site-packages/kedro_mlflow/pipeline/pipeline_ml.py", line 168, in only_nodes_with_namespace
    raise NotImplementedError(MSG_NOT_IMPLEMENTED)
NotImplementedError: This method is not implemented because it does not make sense for 'PipelineML'. Manipulate directly the training pipeline and recreate the 'PipelineML' with 'pipeline_ml_factory' factory.

```

```
  File "repo/venv/lib/python3.10/site-packages/kedro_viz/data_access/repositories/modular_pipelines.py", line 62, in populate_tree
    rest_of_the_pipeline = pipeline - sub_pipeline
  File "repo/venv/lib/python3.10/site-packages/kedro_mlflow/pipeline/pipeline_ml.py", line 239, in __sub__
    raise NotImplementedError(MSG_NOT_IMPLEMENTED)
NotImplementedError: This method is not implemented because it does not make sense for 'PipelineML'. Manipulate directly the training pipeline and recreate the 'PipelineML' with 'pipeline_ml_factory' factory.

```


## Workaround

Quick and dirty implementation in PipelineML class:

```py
def only_nodes_with_namespace(
    self, node_namespace: str
) -> "Pipeline":  # pragma: no cover
    [HIDDEN]
```

```py
def __sub__(self, other):  # pragma: no cover
      [HIDDEN]
```

Can't use `self._turn_pipeline_to_ml(...)` here as the pipelines are not consistent anymore

## Your Environment

<!-- Include as many relevant details about the environment in which you experienced the bug: -->

* `kedro` and `kedro-mlflow` : 0.19.6 and 0.12.2
* Python version used (`python -V`): 3.10.11
* Operating system and version: M2 Sonoma 14.5

## Does the bug also happen with the last version on master?

Probably yes

### Additional contract requirements

- Add a public method `PipelineML.only_nodes_with_namespace(self, node_namespace: str) -> Pipeline` in module `kedro_mlflow.pipeline.pipeline_ml`. It returns a plain Kedro `Pipeline` (not a `PipelineML`) containing only the training nodes whose namespace matches `node_namespace`, and it logs a warning.
- Add a public method `PipelineML.__sub__(self, other) -> Pipeline` in module `kedro_mlflow.pipeline.pipeline_ml`. It returns a plain Kedro `Pipeline` (not a `PipelineML`) containing the nodes that remain when `other` is subtracted from the training pipeline, and it emits a warning.
- The warning emitted by both methods must contain the exact substring `kedro-viz but should never be`.
