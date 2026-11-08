cargo-generate doesn't work with repos in 'detached HEAD' status
Repro:
1. Create `dummy` directory
2. `git init`
3. Add a `dummy` file
4. `git add dummy`
5. `git commit -m "Initial commit"`
6. Edit `dummy`
7. `git add -u`
8. `git commit -m "Commit 2"`
9. `git checkout HEAD^`
10. `cargo generate --name dummy --git .\`

```
cargo generate --name dummy --git .\
Creating project called `dummy`...
Error:  Git Error: A repo has no Head
```

This is a common state to be in during PR CI scenarios.

Treating a checked out template as a folder, as opposed to a repo, would help a lot (https://github.com/cargo-generate/cargo-generate/issues/387) but not sure we'll fall into this check https://github.com/cargo-generate/cargo-generate/commit/d2211d28e8ad4d51856323e9ba7e7879dabae163. Ideally, a --directory or --folder parameter would be added instead of this fall-through behavior.

See also:
https://github.com/actions/checkout/issues/6

### Additional contract requirements

- Add a `--path <path>` command-line option that uses a local directory as the template source instead of cloning a git repository.
- The public `Args` struct (re-exported from the crate root) gains a field `path: Option<PathBuf>`.
- Exactly one of `--git` or `--path` must be supplied; supplying neither, or supplying both, is an error.
- `--path` cannot be combined with `--git` or with a subfolder argument.
- When a local path is supplied together with a favorite name, the local path is used as the template source.
- A favorite defined in the configuration file may specify a local template directory with a `path` key.
- If the supplied path does not exist or cannot be read, generation fails with an error.
- When generating from a local path, the generated repository is initialized on the branch given by `--branch`, or on `main` if `--branch` is not given.
