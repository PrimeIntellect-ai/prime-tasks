Add filter arg to tarfile.extractall call to safely deserialize dataframes
Update `tarfile.extractall` call to safely deserialize dataframes.

### Additional contract requirements

- When the `filter` argument is supported, `tarfile.extractall` must be called with `filter="data"` so that archives are extracted safely.
- If safe extraction is unavailable because the Python version does not support the `filter` argument, raise a `RuntimeError` whose message contains `Please upgrade your Python version`.
