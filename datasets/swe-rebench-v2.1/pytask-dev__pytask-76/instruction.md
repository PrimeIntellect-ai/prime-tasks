BUG: Need graceful error message when passing a path object as `depends_on`
- [x] I have checked that this issue has not already been reported.

- [x] I have confirmed this bug exists on the latest version of pytask.

- [ ] (optional) I have confirmed this bug exists on the `main` branch of pytask.

---

#### To reproduce

Pass a pathlib.Path object as dependency to some task which points to a file that does not exist.

#### Problem description

The error message is cryptic even to the semi-initiated and it does not provide information on which file
```pytb
Traceback (most recent call last):
  File "/home/xxx/miniconda3/envs/epp/lib/python3.8/site-packages/_pytask/resolve_dependencies.py", line 144, in _check_if_root_nodes_are_available
    dag.nodes[node]["node"].state()
  File "/home/xxx/miniconda3/envs/epp/lib/python3.8/site-packages/_pytask/nodes.py", line 180, in state
    raise NodeNotFoundError
_pytask.exceptions.NodeNotFoundError

During handling of the above exception, another exception occurred:

ValueError: A node must be defined in a child of 'paths'.
```

#### Expected Output

At a very minimum, line 180 of `nodes.py` should become

```
[HIDDEN]
```
but a more graceful error message pointing the user at what is causing this might be useful!

### Additional contract requirements

- Add a public function `relative_to(path, source, include_source=True)` in module `_pytask.path`. It returns `path` made relative to `source`. When `include_source` is true the result keeps the name of `source` as a prefix; when false only the part after `source` is returned.
- Add a public function `find_closest_ancestor(path, potential_ancestors)` in module `_pytask.path`. It returns the closest ancestor of `path` among `potential_ancestors`, or `path` itself if it matches a candidate, or `None` if none match.
- Add a public function `find_common_ancestor(*paths)` in module `_pytask.path`. It returns the deepest directory that is a parent of all supplied absolute paths and raises `ValueError` if any path is relative or if the paths share no common ancestor.
- The missing-dependency error identifies the file even when it is not located inside any configured path.
