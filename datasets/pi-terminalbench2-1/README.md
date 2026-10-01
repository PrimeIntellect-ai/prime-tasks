# PI-TerminalBench2.1

Prime Intellect's reviewed Terminal-Bench 2 variant: 82 Harbor tasks with revised
instructions, graders, reference solutions, and dependency provisioning.

Imported from
[`PrimeIntellect-ai/prime-envs@1b98c03b15`](https://github.com/PrimeIntellect-ai/prime-envs/tree/1b98c03b15/environments/terminal/pi_terminalbench2_1),
including the Caffe solver-log date-format correction. The upstream baseline is
`harbor-framework/terminal-bench@3b5caaa4863d64dda7f0957bf4fc2d4f019202d4`.
Task authorship, canary markers, and the upstream [Apache 2.0 license](LICENSE)
are preserved. This dataset is separate from the two upstream-compatible QEMU
repairs in [`../terminal-bench-2`](../terminal-bench-2).

The `pi-terminalbench2-1` environment in `prime-envs` loads this directory through
the native Verifiers Harbor integration, pinned to a Git commit. Task data and
author checks live here; the Python environment package owns only the loader.

## Task contract

- 82 tasks, preserving their declared resources and agent/verifier timeouts.
- 80 tasks disable external network access. `build-pov-ray` and `code-from-image`
  retain public access; local services remain available in offline tasks.
- `gpt2-codegolf` and `model-extraction-relu-logits` use separate verifier images
  and transfer only their declared submission artifacts.
- Seven upstream tasks are excluded: `compile-compcert`,
  `extract-moves-from-video`, `install-windows-3-11`, `mcmc-sampling-stan`,
  `mteb-leaderboard`, `mteb-retrieve`, and `protein-assembly`.

The import preserves all task-file contents except the image references in
`task.toml`, which now identify the existing Prime images. It does not change
prompts, scoring rules, solutions, data assets, or task selection.

## Images

Each manifest is authoritative for its image references: 82 solver images and
two separate verifier images. These `prime/primeintellect/pitb21-*` artifacts
are currently private and require Prime Intellect team access. The task files
are public; image visibility is a separate registry setting.

The references identify the completed images used for the reviewed source
revision. They do not use mutable `latest` tags. The Caffe correction changes
its staged verifier only, so its solver image remains the `661a2f2` image.

Build selected images locally from the repository root:

```bash
uv run scripts/pi-terminalbench2-1/build_images.py --dry-run
uv run scripts/pi-terminalbench2-1/build_images.py caffe-cifar-10
```

The helper builds each selected solver image and any declared separate verifier
image from the adjacent Dockerfile, with Linux amd64 as the default platform.
For Prime VM builds, use the Prime CLI with the same context, choose a new tag
when build inputs change, and update the manifest to the returned reference.
For example:

```bash
prime images push pitb21-caffe-cifar-10:<new-tag> \
  --context datasets/pi-terminalbench2-1/caffe-cifar-10/environment --private
```

Shared verifiers receive their packaged `tests/` files at grading time. Separate
verifier images own their tests: changing packaged files alone does not update
an already-built separate verifier image.

## Author checks

Run the migrated grader regression checks without executing benchmark solutions
or creating sandboxes:

```bash
uv run --python 3.12 scripts/pi-terminalbench2-1/check.py -q
```

The suite checks grader acceptance/rejection behavior and verifier setup and
lifecycle behavior. Linux privilege-boundary checks are skipped on other hosts.
These checks do not establish that all reference solutions pass end to end;
the port does not constitute a new benchmark evaluation.
