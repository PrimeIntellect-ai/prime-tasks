# JobBench import and image

`import_tasks.py` exports the official Harbor tasks from `Job-Bench/job-bench-eval` at `660b33a86ed032559df0b2fdc1ad38cf7ceb83f3` and `JobBench/job-bench` at `d43a66575635da0d3f6cb9a20976dc1a60f3ffc9`. The output contains 65 main tasks and 63 easy tasks. `datasets/jobbench/provenance.json` records source hashes and revisions.

```zsh
git clone https://github.com/Job-Bench/job-bench-eval.git /tmp/jobbench-upstream
git -C /tmp/jobbench-upstream checkout 660b33a86ed032559df0b2fdc1ad38cf7ceb83f3
uv run scripts/jobbench/import_tasks.py /tmp/jobbench-upstream
```

The dependency-only image starts with upstream's pinned LibreOffice calculation runtime and installs the upstream solver and verifier Python dependency sets into separate virtual environments. It contains no task inputs, rubrics, or grader. Build it with:

```zsh
prime switch primeintellect
prime images push jobbench:660b33a --context scripts/jobbench/image \
  --dockerfile scripts/jobbench/image/Dockerfile --public --plain
```

The public image reference is `prime/primeintellect/jobbench:660b33a`. Each task uploads its starter files into the solver workspace. The verifier uses a fresh copy of this image; only `/workspace/output` is declared as a submission artifact, and Harbor stages tests after the solve.

Compared with the upstream generated package, the import selects this image, removes both per-task Dockerfiles so Harbor stages the packaged files, and changes `test.sh` to use `/opt/jobbench-verifier/bin/python`. The default judge is Prime's `openai/gpt-5.6-luna`, with `PRIME_API_KEY` resolved only for grading. Override the verifier environment to reproduce upstream's xAI `grok-4.3` judge. The wrapper prompt, task instructions, inputs, rubrics, judge code, and extraction helpers remain unchanged.
