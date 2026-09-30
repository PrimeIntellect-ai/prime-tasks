# ProgramBench

The 200 ProgramBench tasks exported from the upstream Harbor dataset proposal at
[bencalvert04/harbor-datasets@3e438b1](https://github.com/bencalvert04/harbor-datasets/tree/3e438b1706ffad23308db57fb681a3ac3f9c30d4/datasets/programbench).
The upstream calculator fixture is excluded. Instructions, source images, oracle
solutions, hidden-test metadata, and evaluator scripts are preserved.

Each `tests/Dockerfile` is built unchanged as a public Linux amd64 Prime image:

```text
prime/primeintellect/programbench-verifier.x86.<task-directory>:3e438b1
```

The task manifest adds that image to `[verifier.environment].docker_image`.
The explicit `[verifier].user = "root"` field is omitted because the verifier
images already run as root; the Verifiers Harbor loader does not accept user
overrides. Verification remains in a separate sandbox, with only declared
artifacts transferred from the solver.

The verifier image removes the reference workspace at build time and includes
the upstream tests and evaluator. Hidden test blobs are fetched by the upstream
evaluator when needed. Test suites share a verifier sandbox, with the upstream
workspace restoration and process cleanup between suites.

## Rebuild the verifier images

From the repository root, generate a manifest with the Prime CLI's documented
JSONL format (one entry per task):

```json
{"image":"programbench-verifier.x86.htop-dev--htop.523600b:3e438b1","context":"datasets/programbench/htop-dev--htop.523600b/tests","platform":"linux/amd64"}
```

Then build and publish using the configured Prime Intellect team:

```bash
prime images push-bulk --manifest verifier-builds.jsonl --public --plain
```

Select a new tag for changed build inputs and update each task manifest to the
returned image reference. The `programbench_env` package in `prime-envs` loads
these tasks through the native Harbor integration.
