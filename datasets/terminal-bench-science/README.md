# Terminal-Bench-Science: repaired TESS transit vetting

`tess-transit-vetting` is exported in full from Harbor Hub's
`terminal-bench-science/terminal-bench-science` package at
`sha256:91531bf50016a7c64f6cc60794a17c64c6b2c14858a8ae0de39ca16f2abd611a`.
The upstream task is by Bo Chen (The University of Hong Kong), from
[harbor-framework/terminal-bench-science](https://github.com/harbor-framework/terminal-bench-science),
and retains its [Apache 2.0 license](LICENSE), attribution, and benchmark canary.

The verifier creates `/run/vetter-runs` and `/run/lock` at grading startup before
setting their ownership and permissions. Prime VM boot mounts a fresh tmpfs at
`/run`, hiding directories created while building the image. The instructions,
fixtures, reference solution, scientific checks, and pass thresholds are unchanged.
`task.toml` declares the existing agent image and a separately versioned repaired
verifier image.

Build the verifier image from this directory:

```bash
uv run prime images push \
  terminal-bench-science-verifier.x86.tess-transit-vetting:91531bf50016-run-dirs-v1 \
  --context tess-transit-vetting/tests --public
```

The `terminal-bench-science` taskset in `prime-envs` consumes this task through a
pinned repository commit and keeps the other tasks on their upstream snapshot.
