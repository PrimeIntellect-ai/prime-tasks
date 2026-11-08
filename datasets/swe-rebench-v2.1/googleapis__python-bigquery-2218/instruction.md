AccessEntry.from_api_repr != AccessEntry when entity_type = view
AccessEntry.from_api_repr results in an object that is not equal to the same access entry object instantiated directly.

#### Environment details

  - OS type and version: Linux
  - Python version: `python --version`  3.12.8
  - pip version: `pip --version` 24.3.1
  - `google-cloud-bigquery` version: `pip show google-cloud-bigquery` > 3.31.0 (the bug does not exist in versions <= 3.31.0)

#### Steps to reproduce

  1. Instantiate the same access entry using two different methods
  2. Equality test fails

#### Code example

```python
entry1 = bigquery.dataset.AccessEntry(
        entity_type="view",
        entity_id={
            "projectId": "my_project",
            "datasetId": "my_dataset",
            "tableId": "my_table",
        },
    )

entry2 = bigquery.dataset.AccessEntry.from_api_repr(
      {
            "view": {
                "projectId": "my_project",
                "datasetId": "my_dataset",
                "tableId": "my_table",
            }
      }
)

assert entry1 == entry2
```
