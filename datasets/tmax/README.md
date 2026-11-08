# tmax

[TMax v1.1](https://wai-org.com/blog/tmax-v1-1/) Harbor task corpus, 13,565 tasks. Exported unchanged from [`TMaxxx/tmax-13k-v1.1-harbor`](https://huggingface.co/datasets/TMaxxx/tmax-13k-v1.1-harbor) at revision `5305c26042bf4c312fe24cb1b6e3191a0057040a` (`tasks.zip` sha256 `37398f8cae62482f0cbdd2ff85015f8b4b86c7df8665311b2a704184ea5b03cd`), the same release as Harbor Hub `tmax/tmax-13k-v1.1@v1.1`.

Each task's audit and repair record is in `[metadata]` of its `task.toml` (`rubric_label`, `repair_status`, `validation_status`, `known_verifier_defect`). `environment/Dockerfile` wraps the public base image named in `[metadata].docker_image`. No task sets `[environment].docker_image`.

Released under [ODC-BY](https://opendatacommons.org/licenses/by/1-0/). Gemini 3.1 Pro outputs in the data remain subject to [Google's Terms of Service](https://policies.google.com/terms).
