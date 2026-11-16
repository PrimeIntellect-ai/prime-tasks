Dynamic tree root detection
**Is your feature request related to a problem? Please describe.**

Sometimes the project root cannot be easily identified, for example by generic tools such as treefmt wrappers.

This came up while reviewing `pkgs.nixfmt-tree`, a wrapper tool that uses treefmt to make nixfmt easier to use in simple scenarios.

In an ideal world, we wouldn't have to do any work to identify the root of the project. However `treefmt` is used in many scenarios, so I don't think that'll ever be possible.

**Describe the solution you'd like**

I think the most generic solution would be to allow configuring a script (or other executable) that can be used to test whether or not a given directory is the project root.

I propose adding a new setting: `tree-root-tool`, `tree-root-test`, `tree-root-exe` (or some other name). When defined, the specified script would be run instead of testing for `tree-root-file`.

The script could _either_ be passed the directory being tested as a CLI argument or be run with that directory as its current working directory (or both, I guess).

If the script exits 0, the directory is the root. If the script exits 1, the directory is not the root. If the script has another exit code, an error has occurred.

Perhaps it would be simpler to call the script with the starting directory and have it print the root directory to stdout. That way, such a script could be implemented using `git rev-parse --show-toplevel`. This also has the advantage that the script only needs to be invoked once.

Maybe both approaches could be supported by using multiple setting names, or by reading stdout before falling back to the exit code strategy. Although this feels a little excessive.

**Describe alternatives you've considered**

Alternatively, we could define `tree-root-file` or `tree-root-files` as a list of files, any of which being present would indicate the project root. This may be nice to have, but isn't as powerful as running some arbitrary executable.

Another alternative may be for `nix fmt` to support specifying the flake root, e.g. as an environment variable. This would be useful, but is out of the hands of treefmt and is only useful when treefmt is being run via `nix fmt`.

Another alternative may be to offer an setting that tells treefmt to find the root using `git rev-parse --show-toplevel` instead of looking for `tree-root-file`.

For simple tools like `nixpkgs-tree`, it'd probably also be ok to _not_ attempt to find the project root at all, and instead always treat the current working directory as the tree's root. That way we wouldn't have to try and guess at how to detect the project root. Perhaps an option to enable this behavior could be added?

**Additional context**

- https://github.com/NixOS/nixpkgs/pull/384857#discussion_r1979553258
- https://github.com/NixOS/nixpkgs/pull/384857#issuecomment-2698764313

cc @jfly @infinisil

### Additional contract requirements

Configure command-based root detection with the `tree-root-cmd` setting, which is available as a configuration value, the `--tree-root-cmd` option, and the `TREEFMT_TREE_ROOT_CMD` environment variable. The command writes the project-root path to standard output, and treefmt uses that path as the root for traversal. Evaluate the command in the context of the effective working directory being examined, either by using that directory as its working directory or by making that directory available to it as an argument.
