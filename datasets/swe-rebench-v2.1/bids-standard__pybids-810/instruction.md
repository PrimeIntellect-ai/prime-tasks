X specification doesn't allow regex pattern matching/completion for variable names
Example use case:
```
...
 "Model": {
        "X": ["trials", "gain", "loss", "demeaned_RT", "rot_*", "trans_*", 1]
      },
...
```

Error message:

```
Traceback (most recent call last):
  File "/home/shank/miniconda3/envs/fitlins38_2/bin/fitlins", line 33, in <module>
    sys.exit(load_entry_point('fitlins', 'console_scripts', 'fitlins')())
  File "/home/shank/dev-packages/fitlins-local/fitlins/cli/run.py", line 434, in main
    sys.exit(run_fitlins(sys.argv[1:]))
  File "/home/shank/dev-packages/fitlins-local/fitlins/cli/run.py", line 427, in run_fitlins
    report_dict = build_report_dict(deriv_dir, work_dir, graph)
  File "/home/shank/dev-packages/fitlins-local/fitlins/viz/reports.py", line 68, in build_report_dict
    load_all_specs(all_specs, None, graph.root_node)
  File "/home/shank/dev-packages/fitlins-local/fitlins/utils/bids.py", line 46, in load_all_specs
    specs = node.run(group_by=node.group_by, force_dense=False)
  File "/home/shank/dev-packages/pybids/bids/modeling/statsmodels.py", line 460, in run
    node_output = BIDSStatsModelsNodeOutput(
  File "/home/shank/dev-packages/pybids/bids/modeling/statsmodels.py", line 604, in __init__
    raise ValueError("X specification includes variable(s) {}, but "
ValueError: X specification includes variable(s) ['trans_*', 'rot_*'], but these were not found in data matrix.
```

cc: @effigies

### Additional contract requirements

- Add a public function `expand_wildcards(selectors, pool)` in module `bids.modeling.statsmodels`. It returns a new list in which every selector containing a shell-style wildcard (`*`, `?`, or `[]`) is replaced, at its original position, by all entries of `pool` that match it. Selectors with no matches are omitted, literal selectors are kept unchanged, and the order of the original selectors is preserved. The input list is not modified.
- The statsmodels node resolves wildcard variable names in a model's `X` specification against the available variables before building the design matrix, so that specifications such as `rot_*` or `trial_type.*` select every matching variable.
