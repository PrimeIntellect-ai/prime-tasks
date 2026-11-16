Password store path in the config file strips "~"
In my config file I have the path to the password store as:

```
root:
  path: gpgcli-gitcli-fs+file://~/.local/share/password-store
```

The 1.7.0 version stopped recognizing it as the "home" path and it strips it.

The exact error is:

```
Error: failed to list store: lstat /.local/share/password-store: no such file or directory
```
