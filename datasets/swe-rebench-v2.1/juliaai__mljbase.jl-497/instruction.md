Remove initialisation of remote channels.
In MLJBase the `__init__` function initialises a remote channel called MACHINE_CHANNEL, which is only used for (important) testing purposes. However, this is an obstacle for certain kinds of scaling; see [this discourse thread](https://discourse.julialang.org/t/mlj-and-clustermanagers/51540).

### Additional contract requirements

- The module must expose `MLJBase.TESTING`, which is `true` when the environment variable `TEST_MLJBASE` is `"true"`, and `false` otherwise.
- The remote channel `MACHINE_CHANNEL` must be initialised only when `TESTING` is `true`. When `TEST_MLJBASE` is not `"true"`, `MLJBase.MACHINE_CHANNEL` must not be a `RemoteChannel`.
