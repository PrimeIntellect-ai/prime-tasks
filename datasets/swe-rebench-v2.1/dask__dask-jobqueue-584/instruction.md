SLURMCluster: header_skip should not skip user-defined extra header lines
Currently, with `SLURMCluster`, the user can add arbitrary header lines by adding them to the `job_extra` list. These extra lines [end up in the `job_header` attribute](https://github.com/dask/dask-jobqueue/blob/d7afbfe50191a4dca5f07ee506294edebbe05ad5/dask_jobqueue/slurm.py#L80_L83) right upon initialisation of the cluster.

Before submitting a job, the [`header_skip` list is used to filter all header lines](https://github.com/dask/dask-jobqueue/blob/d7afbfe50191a4dca5f07ee506294edebbe05ad5/dask_jobqueue/core.py#L280_L286) and removes lines matching the skip list even if the user explicitly set them via `job_extra`.

(This came up in #469.)
