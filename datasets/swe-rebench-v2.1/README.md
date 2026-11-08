# SWE-rebench V2.1 RL

Nebius's [SWE-rebench V2.1 RL](https://hub.harborframework.com/datasets/ibragim-badertdinov/swe-rebench-v2.1-rl):
13,337 issue-resolution tasks in 20 languages, repaired from
[SWE-rebench V2](https://huggingface.co/datasets/nebius/SWE-rebench-V2)
([paper](https://arxiv.org/abs/2602.23866)).

Exported verbatim from Harbor Hub package `ibragim-badertdinov/swe-rebench-v2.1-rl`, revision 3
(published 2026-11-05), digest
`sha256:0dcba0d99e8c2bc7f1a8aefdd2e3cf8f5aae2387659d6390a06446ed5f3612b3`. SWE-rebench V2 is
licensed CC-BY-4.0; each task's repository keeps its own license. To export again:

```bash
uv run scripts/swe-rebench-v2.1/import_tasks.py
```

The `swerebench_v2` environment in `prime-envs` loads this directory through the native
Verifiers Harbor integration, pinned to a Git commit.

## Task contract

- `task.toml` pins a public Docker Hub image by digest (`docker.io/swerebenchv2/...`) and declares
  6 CPUs, 24 GiB of memory, 32 GiB of storage, a 3,000 s agent timeout, and a 2,400 s verifier
  timeout. `[metadata]` holds `repo`, `language`, `log_parser`, and `quality_flags`; 159 tasks are
  flagged `weak_f2p`.
- `tests/test.sh` restores the files that `tests/test.patch` touches, applies it, runs the test
  command, and grades the log with `tests/grade.py`, a standard-library grader, against the
  FAIL_TO_PASS and PASS_TO_PASS lists in `tests/config.json`. The reward is 1 when every
  FAIL_TO_PASS test passes and no PASS_TO_PASS test fails.
- `solution/solve.sh` applies the reference patch `solution/gold.patch`.

## Changes relative to SWE-rebench V2

Upstream reports that LLM judges reviewed statements and tests, repairing defects or removing the
task; that images were audited for leaked fixes and tests and rebuilt where needed; that the Jest,
Mocha, and Julia parsers and duplicate test names were fixed; and that tasks with a failing
reference patch or an unstable environment were removed.

Compared with their SWE-rebench V2 rows:

| Change | Tasks |
| --- | ---: |
| Statement gains an `Additional contract requirements` section naming the interface the tests check | 7,035 |
| Solution hints in the statement replaced with `[HIDDEN]` | 1,851 |
| Test patch changed | 9,931 |
| FAIL_TO_PASS set changed | 8,074 |
| PASS_TO_PASS set changed | 6,849 |
| Test command changed | 1,220 |
| Reference patch changed (919 drop files outside the tested fix) | 944 |
| Image replaced by a rebuilt image | 183 |

741 statements still link to GitHub pull requests, commits, or comparisons.
