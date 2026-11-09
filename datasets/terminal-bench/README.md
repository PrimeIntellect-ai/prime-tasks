# Terminal-Bench: repaired tasks

This directory contains only `vpp-loss-divergence` and `html-js-filter`,
exported from
[`harbor-framework/terminal-bench@4031b48384a5`](https://github.com/harbor-framework/terminal-bench/tree/4031b48384a5946ba2c5b3c5fa59246ce8d47d92/tasks).
The tasks retain their upstream [Apache 2.0 license](LICENSE).

Task instructions, tests, solutions, resources, and timeouts match upstream. Each
task declares its workspace and verifier images in `task.toml`. Its
`[verifier.environment]` repeats the `[environment]` resources, which the separate
verifier previously copied.

## Repairs

`vpp-loss-divergence`: `tests/pretrain_runner.py` refuses to run the reference
unless `/tests/pretrain.py` and `/tests/config.py` are owned by root. Prime's image
builder keeps the build context's owner on `COPY`, so the published verifier had
`/tests` owned by `501:20`. Every verifier run exited 70 with `unsafe trusted
pretrain input: /tests/pretrain.py` and published no reward. `tests/Dockerfile`
now sets the owner of `/tests` explicitly. With the rebuilt verifier, the untouched
workspace scores 0 and the reference solution scores 1.

`html-js-filter`: the workspace image used CPython 3.12.14, while the verifier runs
the submitted filter with Ubuntu Noble's CPython 3.12.3. Their `html.parser`
modules differ, although the upstream Dockerfile intends the agent to test against
the parser it is graded on. Filters that import parser helpers added after 3.12.3
pass locally and fail in grading with `ImportError`. The workspace now uses
`python:3.12.3-slim-bookworm`, whose `html.parser` and `_markupbase` match the
verifier's byte for byte. The verifier is unchanged.

## Images

| Task | Workspace | Verifier |
| --- | --- | --- |
| `vpp-loss-divergence` | `prime/primeintellect/terminal-bench-vpp-loss-divergence:4031b48384a5` (upstream) | `prime/primeintellect/terminal-bench-vpp-loss-divergence-verifier:4031b48384a5-pi1` |
| `html-js-filter` | `prime/primeintellect/terminal-bench-html-js-filter:4031b48384a5-pi1` | `prime/primeintellect/terminal-bench-html-js-filter-verifier:4031b48384a5` (upstream) |

To build the repaired images from this directory in the PI Research team:

```bash
prime images push terminal-bench-vpp-loss-divergence-verifier:4031b48384a5-pi1 \
  --context vpp-loss-divergence/tests --public
prime images push terminal-bench-html-js-filter:4031b48384a5-pi1 \
  --context html-js-filter/environment --public
```

The `terminal-bench` environment in `prime-envs` loads the other 64 tasks directly
from the upstream snapshot.
