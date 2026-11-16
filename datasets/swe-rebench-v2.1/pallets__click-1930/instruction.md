Shell completion fails with for arguments starting with "/"
After enabling shell completion support, arguments which start with a leading forward slash "/" fail to complete.

After a bit of debugging, it appears that if the argument starts with a "/", the completions are generated for the command itself instead of for the argument. For example, `my_app open /fold⇥` would generate completions for `open` instead of `/fold` whereas `my_app open fold⇥` correctly generates completions for `fold`.

Edit: To clarify the above, in both cases either "/fold" or "fold" is correctly picked up as the incomplete string. But in the first case, `obj.shell_complete(ctx, "/fold")` is called with the "open" command as the `obj`.

Environment:

- Python version: 3.9
- Click version: 8.0.1
- Shell: zsh, bash
