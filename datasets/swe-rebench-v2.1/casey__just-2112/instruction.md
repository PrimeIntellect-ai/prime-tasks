Improve `--list` output with modules
Collecting feedback from #929.

To sum up:
1. [ ] `--list` output with modules is too verbose and nested
2. [x] It should be possible to do `--list SUBMODULE` and only see `--list` output for that submodule, and iteratively descend into submodules with

For 1, I think I agree. The current output is very verbose and gets unwieldy quickly if there are a lot of submodules, and gets quite nested if the module hierarchy is deep. I think that, by default, `--list` should not print out the recipes in submodules, but only the submodules themselves.

So something like:

```
$ just --list
Available recipes:
  foo
  bar

Available submodules:
  baz
  bob
```

If there are no recipes at the top level, it would just be:

```
$ just --list
Available submodules:
  baz
  bob
```

I'm undecided about whether to completely remove the nested output, or require `--verbose` or `--nested` or whatever to get it.

For 2, I'm working on a patch that allows `--list` to take a module path, which are space- or `::`- separated module names, and will descend into that module, and only print the `--list` output for that module.

@gl-yziquel and @valscion what do you think?

### Additional contract requirements

The `--list` output format is:

- The heading is always the configured list heading, which defaults to
  `Available recipes:`. It is printed even when the listed module has no recipes
  of its own.
- Each public recipe is printed on its own line, indented with the list prefix
  (default four spaces).
- Each submodule is printed after the recipes on its own line, indented with the
  list prefix, as the submodule name followed by ` ...` (a space and three
  periods).

For example, a justfile with top-level recipes `foo` and `bar` and submodules
`baz` and `bob` lists as:

```
Available recipes:
    foo
    bar
    baz ...
    bob ...
```

`--list` also accepts a module path made of space- or `::`-separated module
names and prints the list for the named module only. An invalid module path
(for example one containing `$`) fails with the message
"Invalid module path `<path>`" (prefixed by `error: `), where `<path>` is the
path joined by spaces. A path naming a submodule that does not exist fails with
the message "Justfile does not contain submodule `<path>`" (prefixed by
`error: `).


- Submodules are listed in the order in which they are declared in the justfile.
