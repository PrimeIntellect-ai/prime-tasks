`dwave install` broken on py39 after utils refactor
Due to a change in `entry_points()` behavior across a few versions of python (see compatibility note in [docs](https://docs.python.org/3/library/importlib.metadata.html#entry-points)), [HIDDEN]

However, during utils refactor in #628, we switched to `importlib.metadata`. This causes failure of `get_contrib_config` (used from `dwave install` and `dwave setup` CLI commands) on Python 3.9 (only!).

https://github.com/dwavesystems/dwave-cloud-client/blob/30d69493a5f3b3fdaeeda872d253d5b735ad8fa0/dwave/cloud/utils/dist.py#L36
