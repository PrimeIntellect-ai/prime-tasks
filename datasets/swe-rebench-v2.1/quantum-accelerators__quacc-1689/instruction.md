Using environment variables, there is no easy way to set a setting as `None`
### What would you like to report?

I use parsl but I often want to do quick tests without workflow engines.

For this I would like to be able to do something like export QUACC_WORKFLOW_ENGINE = "local" or QUACC_WORKFLOW_ENGINE =

But this gets shutdown by an error. "  Input should be 'covalent', 'dask', 'parsl', 'prefect', 'redun' or 'jobflow' [type=literal_error, input_value='', input_type=str]"

Currently I have no way to run them locally, since I have parsl installed, quacc will by default set the workflow engine setting to parsl.

### Additional contract requirements

- Setting an environment variable to `None`, `null`, or `none` results in the Python value `None`.
- A custom YAML setting written as `None` or `null` results in the Python value `None`.
