# ProgramBench

The 200 ProgramBench tasks exported from the upstream Harbor dataset proposal at
[bencalvert04/harbor-datasets@3e438b1](https://github.com/bencalvert04/harbor-datasets/tree/3e438b1706ffad23308db57fb681a3ac3f9c30d4/datasets/programbench).
The upstream calculator fixture is excluded. Instructions, source images, oracle
solutions, test cases, and evaluator scripts are preserved. Task-specific verifier
settings account for demonstrated environment incompatibilities:

- oha uses `branch_env.NO_COLOR = "true"`; its CLI rejects the value `"1"`.
- age disables the suite-wide `script` PTY so non-TTY passphrase tests return
  instead of prompting. Tests requiring a terminal create their own.

Each `tests/Dockerfile` is built as a public Linux amd64 Prime image. The imported
images use:

```text
prime/primeintellect/programbench-verifier.x86.<task-directory>:3e438b1
```

Each task's `[verifier.environment].docker_image` is authoritative. oha pins a
rebuilt image containing its corrected test metadata. Dedicated verifier images
own `/tests`; changing packaged tests or metadata alone does not update grading.
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
uv run --no-project prime images push-bulk --manifest verifier-builds.jsonl --public --plain
```

Select a new tag for changed build inputs and update each task manifest to the
returned image reference. The `programbench_env` package in `prime-envs` loads
these tasks through the native Harbor integration.

## Validate oracle results

Run both controls without a model, using the published images and VF's native
artifact transfer and separate-verifier lifecycle:

```bash
uv run scripts/programbench/validate.py --output /path/to/programbench-qc
```

Use `--task <directory-name>` to select a task, or `--control gold|empty` to run
one control. The command checks all selected manifests before provisioning,
retains logs and runtime IDs, and exits unsuccessfully if any control fails.
Gold also checks that normal hard links and confined relative symlinks survive
artifact transfer and that the verifier initially contains no reference binary.
Successful results are reusable only for the same task-file fingerprint; failed
and stale attempts are retained when rerunning the command.

Run the oracle through the native solver-to-fresh-verifier path and retain
`programbench_eval.json`, `harbor_diagnostics.json`, and `reward.json`. Then check
the saved logs against the exact task metadata used by the verifier:

```bash
uv run --no-project scripts/programbench/check_oracle.py \
  datasets/programbench/filosottile--age.706dfc1 /path/to/saved/verifier-logs
```

This author-side gate requires a nonempty applicable-test set, every applicable
test passing, no top-level or branch errors, and consistent reward/diagnostic
files. It lists missing cases even when `infra_error` is zero. A zero reward or
partial oracle is not a validation pass. This gate does not replace candidate
scoring or classify every candidate timeout as infrastructure failure.

Use VF's safe artifact-link support (verifiers PR #2710 or a later version
containing it) when validating realistic Rust submissions. `.gitignore` does not
filter the declared workspace artifact handoff.

The imported oracle reconstructs the reference executable; it does not establish
that an original-source gold patch builds on a fresh checkout. Validate empty
submissions separately (expected reward zero) and retain the underlying failure
reason so a broken grader cannot masquerade as a successful negative control.
