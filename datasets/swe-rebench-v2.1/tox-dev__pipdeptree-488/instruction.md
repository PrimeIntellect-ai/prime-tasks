Implement `--exclude-dependencies` to make `--exclude` exclude a package's dependencies
### Describe the feature

Related discussions are [here](https://github.com/tox-dev/pipdeptree/discussions/434) and [here](https://github.com/tox-dev/pipdeptree/issues/452).

Currently, `--exclude` does its job of excluding packages from the dependency tree. This is fine, but when there are times when we also want to remove their dependencies from the output the current implementation doesn't make this possible.

This issue proposes an `--exclude-dependencies` flag that will have pipdeptree take this additional step of removing dependencies from the output.

In the future major versions, it may make sense to just make this the default behavior of `--exclude`. But to avoid a breaking change, it should just be a flag for now.

### Additional contract requirements

- The `--exclude-dependencies` CLI option sets the parsed `Options.exclude_dependencies` attribute to true; when the option is not supplied the attribute is false.
- When `--exclude-dependencies` is supplied together with `--exclude`, the CLI applies the dependency pruning to the rendered dependency tree, so the excluded packages' dependency sub-trees are removed from the output.
- Without `--exclude-dependencies`, `--exclude` continues to exclude the matching package without pruning its dependencies from the output.
