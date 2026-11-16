Option to skip/control which hook files are created during init
## Description
<!-- Clearly describe what you are suggesting/requesting. -->
Add a feature that allows for controlling which hook files are instantiated

## Value
<!-- Clearly and succinctly explain the benefits of what you are suggesting/requesting. -->
Currently, the repo initialization process (triggered with either `rusty-hook init` or using compiling with rusty-hook as a dev dep) adds a hook file for all the supportable client side hooks to easily support user configurability. However, there are probably some advanced user scenarios where they'd like to control which hook files are/aren't created.

For example, there are other Rust tools that support creating their own hook files (for example [git-journal](https://github.com/saschagrunert/git-journal#commit-message-preparation-and-verification) which supports commit message hooks) and we should support users that may want to use rusty-hook in conjunction with those others. There's also the potential for some users to want really fine grained control (create the `pre-commit` file but none of the others)

## Implementation Thoughts
I think the most common usage of this feature would be a skipping of one or two hook files (like `commit-msg` and _perhaps_ `prepare-commit-msg`) so my initial inclination would be to support this via a new config option skip list, for example:

```toml
hook_file_skip_list = [
  "commit-msg"
]
```

If there's sufficient demand down the road to support an opt-in type feature over an opt out, we could add an additional config at that time for an include/allow list and figure out precedence if and when we get there (implementing this as a skip/opt-out won't preclude doing more work in the future).

Currently, the init process that sets up the hook files in the repo just iterates through the full list of hooks:
https://github.com/swellaby/rusty-hook/blob/39fbca3b90c6f37bfdacd23bc4d25b9a0da554f0/src/hooks.rs#L75-L80

(side note `create_hook_files` has a lot of duplication that could be consolidated into a separate closure or function)

[HIDDEN]

Would then need to shuffle up the init order a bit to run the config creation check first, and then check for the `hook_file_skip_list` presence/value to pass along to `setup_hooks` function flow
https://github.com/swellaby/rusty-hook/blob/39fbca3b90c6f37bfdacd23bc4d25b9a0da554f0/src/rusty_hook.rs#L10-L36

### Additional contract requirements

The `init` command accepts a comma-separated `--skip-hook-list` value of hook names. During initialization, each named hook file is omitted and supported hook files not named in the value are still created.

The hook-file skip list is a list of hook names (strings) for which no hook file is created.

The initialization flow exposes these public functions, each of which must honor the supplied skip list so that no hook file is created for a skipped hook name:

- `setup_hooks(run_command, write_file, root_directory_path: &str, hook_file_skip_list: &Vec<&str>) -> Result<(), String>` in the `git` module (`src/git.rs`).
- `create_hook_files(write_file, root_directory_path: &str, hooks_directory: &str, hook_file_skip_list: &Vec<&str>) -> Result<(), String>` in the `hooks` module (`src/hooks.rs`).
- `init(run_command, write_file, file_exists, hook_file_skip_list: Vec<&str>) -> Result<(), String>` in the `rusty_hook` module (`src/rusty_hook.rs`).
