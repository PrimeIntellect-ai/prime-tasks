`--in-diff` fails on diffs mentioning binary files
Suppose that `test.diff` contains git diff output such as:

```diff
diff --git a/test-renderers/expected/renderers/fog-None-wgpu.png b/test-renderers/expected/renderers/fog-None-wgpu.png
index 616d6ea8..afd1b043 100644
Binary files a/test-renderers/expected/renderers/fog-None-wgpu.png and b/test-renderers/expected/renderers/fog-None-wgpu.png differ
```

Then `cargo mutants --in-diff test.diff` will fail:

```
Error: Failed to parse diff: Line 1: Error while parsing: diff --git a/test-renderers/expected/renderers/fog-None-wgpu.png b/test-renderers/expected/renderers/fog-None-wgpu.png
index 616d6ea8..afd1b043 100644
Binary files a/test-renderers/expected/renderers/fog-None-wgpu.png and b/test-renderers/expected/renderers/fog-None-wgpu.png differ
```

If the diff contains files preceding this one, the outcome is similar, but as a panic:

```
thread 'main' panicked at /Users/kpreid/.cargo/registry/src/index.crates.io-6f17d22bba15001f/patch-0.7.0/src/parser.rs:84:5:
bug: failed to parse entire input. Remaining: 'diff --git a/test-renderers/expected/renderers/fog-None-wgpu.png b/test-renderers/expected/renderers/fog-None-wgpu.png
index 616d6ea8..afd1b043 100644
Binary files a/test-renderers/expected/renderers/fog-None-wgpu.png and b/test-renderers/expected/renderers/fog-None-wgpu.png differ
'
```

Instead, this diff should successfully parse (and, since binary files are not Rust source code that can be mutated, it should be skipped).

### Additional contract requirements

- For a diff containing only binary-file content, stderr must contain `diff file is empty`.
