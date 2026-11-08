`params_show`: locking issues
`params_show` requires the lock, which breaks in multi-gpu/multi-node training. Need to reconsider whether it's needed and/or recommend another method for reading params, at least in multi-gpu/multi-node scenarios (see https://dvc.org/doc/dvclive/ml-frameworks/pytorch#distributeddataparallel).

### Additional contract requirements

- Reading parameters with `dvc params show` (the `Repo.params.show()` API) must succeed while another process holds the repository lock, so that parameters can be read from multi-GPU or multi-node training jobs without being blocked by that lock.
