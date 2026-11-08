Handle directory symlinks
I was impressed that chezmoi handled symlinked files placed by my previous dotfile manager.  But it seems to have trouble with directory symlinks:
```
$ ls -l ~/.config/omf
lrwxrwxrwx 1 james users 25 Nov 10 16:16 /home/james/.config/omf -> /home/james/.dotfiles/omf

$ ls -ld ~/.dotfiles/omf
drwxr-xr-x 3 james users 4096 Nov 12 22:27 /home/james/.dotfiles/omf

$ chezmoi add -r ~/.config/omf
Error: .config/omf: not a regular file or directory
Usage:
...
2018/11/24 11:28:51 .config/omf: not a regular file or directory

$ chezmoi add -r ~/.config/omf/
Error: .config/omf: not a regular file or directory
Usage:
...
2018/11/24 11:28:53 .config/omf: not a regular file or directory
```

### Additional contract requirements

- Adding a symbolic link, including a symbolic link whose target is a directory, records the symbolic link itself rather than following it. A source file name with the `symlink_` prefix represents a symbolic link: the contents of the source file are the target of the symbolic link, and applying the target state creates a symbolic link at the target path instead of a regular file.
- The `parsedSourceFileName` struct has a field named `mode` of type `os.FileMode`. Parsing a source file name with the `symlink_` prefix sets `mode` to `os.ModeSymlink | 0666`, and `parsedSourceFileName.SourceFileName()` reassembles the source file name, including the `symlink_` prefix for symbolic links.
- In the `chezmoi` package there is a `Symlink` type representing the target state of a symbolic link. It has a `Target` field of type `string` holding the link target and a `sourceName` field of type `string` holding the encoded source file name.


- For a symbolic link source file with the `.tmpl` suffix, render the file contents as a template before using the result as the link target. For example, if `symlink_foo.tmpl` contains `bar-{{ .host }}` and `.host` is `example.com`, the link target is `bar-example.com`.
