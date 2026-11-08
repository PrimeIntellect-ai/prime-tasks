Remove software version defaults
E.g., [`[HIDDEN]`](https://github.com/ResearchObject/ro-crate-py/blob/81d74b3c40241235229500d30b4747a392c65a0b/rocrate/model/softwareapplication.py#L57). No info is better than arbitrary (thus likely wrong) info.

### Additional contract requirements

- When no engine version is supplied, omit the `engineVersion` property from the test definition rather than supplying a default version.
