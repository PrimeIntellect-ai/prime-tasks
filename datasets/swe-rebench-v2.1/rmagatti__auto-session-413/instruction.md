AutoSave ignores current loaded session when there's multiple local cwd's
**Problem:** After leaving Neovim when on a tab with a different local cwd than the restored session's name, session is saved as the cwd name, and not the current loaded session.

**Expected:** If a session is loaded (or has been restored), Autosave should save the loaded session name from `v:this_session`, regardless of the local cwd.

Reproduce:
1. Setup with
```
auto_session_enable_last_session = false,
auto_session_enabled = true,
auto_save_enabled = true,
auto_restore_enabled = true,
```
2. Open `nvim`, open a few files and close Neovim to save the session.
3. Open `nvim` again, session should be restored.
4. Create a new tab, `:tabnew` and `:lcd ~/different/project` and open a file from the other project.
5. Without changing to a different tab, close Neovim.
6. Session name saved is the last tab's cwd, which is unexpected, and ignores `v:this_session` for the current loaded session.

### Additional contract requirements

- When `SaveSession()` is called while the current tab or window has a local working directory, it must save the session for Neovim's global working directory, not that local working directory.
