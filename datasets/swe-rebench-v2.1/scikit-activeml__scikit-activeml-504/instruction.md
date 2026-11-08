BUG: Propagate `random_state` to `cluster_algo` in `TypiClust` and `ProbCover`
### Describe the issue:

Currently, the `random_state` set as `__init__` parameter of the query strategies `TypiClust` and `ProbCover` is not explicitly propagated to the `cluster_algo` but the user must set its `random_state` via `cluster_algo_dict`.

### Reproduce the bug via a code example:

```python
- `TypiClust(random_state=0)` is not deterministic but only `TypiClust(random_state=0, cluster_algo_dict={"random_state": 0})`
- `ProbCover(random_state=0)` is not deterministic but only `ProbCover(random_state=0, cluster_algo_dict={"random_state": 0})`
```

### Error message:

```shell

```

### Context for the issue:

_No response_
