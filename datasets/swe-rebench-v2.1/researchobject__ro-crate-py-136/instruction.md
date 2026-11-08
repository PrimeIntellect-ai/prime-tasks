Fix behavior wrt "missing" data entities
After the merge of #75, we allow data entities whose `@id` does not map to an existing file or directory, even if local. While this adds flexibility for use cases like #73, such crates are not supported by other libraries. Specifically, I got reports of crates generated with ro-crate-py that lead to errors when submission to WorkflowHub is attempted. The main issue is that it's too easy to add a "missing" data entity:

```python
crate.add_file("/this/does/not/exist")  # Adds a File entity with @id = "exist"
```

This means it can be done involuntarily, by simply mistyping the path. It should be harder to do so (advanced usage), and we should issue a warning when it's done.

### Additional contract requirements

- `ROCrate.add_file(source=None, dest_path=None)` accepts `None` as `source` and returns the registered `File` entity.
- `ROCrate.add_dataset(source=None, dest_path=None)` accepts `None` as `source` and returns the registered `Dataset` entity.
- `ROCrate.write(out_path)` raises `OSError` when the crate contains a `File` or `Dataset` entity whose `source` is a local path that does not exist.
- Writing a crate that contains a `File` entity whose `source` is `None` emits a warning and does not create the corresponding file.
- Writing a crate that contains a `Dataset` entity whose `source` is `None` creates an empty directory for it.
