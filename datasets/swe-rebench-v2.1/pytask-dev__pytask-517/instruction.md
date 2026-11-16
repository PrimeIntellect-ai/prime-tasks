ENH: bogus task dir gives unclear error
EDIT: I'm having a hard time repro-ing this. I think I am misunderstanding the root cause. Do you have any idea how this could occur?

Just a nice UX improvement: putting a bogus path in the pyproject.toml gives a weird error:

```toml
[tool.pytask.ini_options]
paths = "does/not/exist"
```

```
╭─────────────────────────────── Traceback (most recent call last) ────────────────────────────────╮
│ /Users/nc/code/scg/kobuk/.venv/lib/python3.11/site-packages/_pytask/collect_command.py:77 in     │
│ collect                                                                                          │
│                                                                                                  │
│    74 │   │   │   tasks = _select_tasks_by_expressions_and_marker(session)                       │
│    75 │   │   │   task_with_path = [t for t in tasks if isinstance(t, PTaskWithPath)]            │
│    76 │   │   │                                                                                  │
│ ❱  77 │   │   │   common_ancestor = _find_common_ancestor_of_all_nodes(                          │
│    78 │   │   │   │   task_with_path, session.config["paths"], session.config["nodes"]           │
│    79 │   │   │   )                                                                              │
│    80 │   │   │   dictionary = _organize_tasks(task_with_path)                                   │
│                                                                                                  │
│ /Users/nc/code/scg/kobuk/.venv/lib/python3.11/site-packages/_pytask/collect_command.py:132 in    │
│ _find_common_ancestor_of_all_nodes                                                               │
│                                                                                                  │
│   129 │   │   │   │   x.path for x in tree_leaves(task.produces) if isinstance(x, PPathNode)     │
│   130 │   │   │   )                                                                              │
│   131 │                                                                                          │
│ ❱ 132 │   return find_common_ancestor(*all_paths, *paths)                                        │
│   133                                                                                            │
│   134                                                                                            │
│   135 def _organize_tasks(tasks: list[PTaskWithPath]) -> dict[Path, list[PTaskWithPath]]:        │
│                                                                                                  │
│ /Users/nc/code/scg/kobuk/.venv/lib/python3.11/site-packages/_pytask/path.py:87 in                │
│ find_common_ancestor                                                                             │
│                                                                                                  │
│    84                                                                                            │
│    85 def find_common_ancestor(*paths: Path) -> Path:                                            │
│    86 │   """Find a common ancestor of many paths."""                                            │
│ ❱  87 │   return Path(os.path.commonpath(paths))                                                 │
│    88                                                                                            │
│    89                                                                                            │
│    90 @functools.lru_cache                                                                       │
│ in commonpath:531                                                                                │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
ValueError: commonpath() arg is an empty sequence
```

It would be nice if it said "this path doesn't exist" or something.

### Additional contract requirements

- If a path listed in the `paths` setting of `pyproject.toml` does not exist, pytask must report an error that names that configured path as missing. It must not fail with an unrelated error about an empty sequence, and the command must not finish successfully.
