# tmax

[TMax v1.1](https://wai-org.com/blog/tmax-v1-1/) Harbor task corpus, 13,565 tasks. Exported from [`TMaxxx/tmax-13k-v1.1-harbor`](https://huggingface.co/datasets/TMaxxx/tmax-13k-v1.1-harbor) at revision `5305c26042bf4c312fe24cb1b6e3191a0057040a` (`tasks.zip` sha256 `37398f8cae62482f0cbdd2ff85015f8b4b86c7df8665311b2a704184ea5b03cd`), the same release as Harbor Hub `tmax/tmax-13k-v1.1@v1.1`, with these changes:

- `[verifier] user = "root"` is removed. The task images already run as root.
- Verifier pytest runs of the staged test file pass `--noconftest -c /dev/null -p no:cacheprovider`, so `conftest.py` or pytest config files the agent leaves in `/tmp` or `/` cannot change the result.
- Each task sets `[environment].docker_image` to a public Prime platform image, and `environment/docker-compose.yaml` is removed. `environment/Dockerfile` is upstream's wrapper and is not built.

## Images

- 8,828 tasks use `tmax/<task-id>:latest`, the v1.0 platform images. They were built from the v1.0 task recipe (`environment/` at prime-tasks `27de1c1b`), which runs the same per-task setup script as the upstream image on Prime's shared tool base.
- 4,737 tasks use the upstream image named in `[metadata].docker_image`, mirrored under the same reference: 1,713 tasks whose v1.1 image differs from v1.0, and 3,024 tasks whose v1.0 image carries extra fixture files that the upstream image does not.

Each task's audit and repair record is in `[metadata]` of its `task.toml` (`rubric_label`, `repair_status`, `validation_status`, `known_verifier_defect`).

Released under [ODC-BY](https://opendatacommons.org/licenses/by/1-0/). Gemini 3.1 Pro outputs in the data remain subject to [Google's Terms of Service](https://policies.google.com/terms).
