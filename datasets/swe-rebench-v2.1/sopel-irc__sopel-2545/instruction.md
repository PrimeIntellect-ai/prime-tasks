Broken plugin symlink -> `PluginError` in CLI
### Description
The `sopel-plugins` command should gracefully handle things that look like plugins but can't be loaded. It does this in some cases (like Python file plugins with syntax errors), but not all. There's room for improvement.

For example, I recently symlinked a file in `~/.sopel/plugins` so it would point to my local repository for that plugin (not yet converted to an entry-point or package) for testing. I did the `ln -s` command wrong, so the link was broken: `pluginfile.py -> ./pluginfile.py`, which is a circular reference.

### Logs
```
Traceback (most recent call last):
  File "/home/dgw/.local/bin/sopel-plugins", line 33, in <module>
    sys.exit(load_entry_point('sopel', 'console_scripts', 'sopel-plugins')())
  File "/home/dgw/github/sopel/sopel/cli/plugins.py", line 556, in main
    return handle_list(options)
  File "/home/dgw/github/sopel/sopel/cli/plugins.py", line 174, in handle_list
    for name, info in plugins.get_usable_plugins(settings).items()
  File "/home/dgw/github/sopel/sopel/plugins/__init__.py", line 225, in get_usable_plugins
    plugins_info = collections.OrderedDict(
  File "/home/dgw/github/sopel/sopel/plugins/__init__.py", line 225, in <genexpr>
    plugins_info = collections.OrderedDict(
  File "/home/dgw/github/sopel/sopel/plugins/__init__.py", line 185, in enumerate_plugins
    for plugin in all_plugins:
  File "/home/dgw/github/sopel/sopel/plugins/__init__.py", line 124, in find_directory_plugins
    yield handlers.PyFilePlugin(abspath)
  File "/home/dgw/github/sopel/sopel/plugins/handlers.py", line 440, in __init__
    raise exceptions.PluginError('Invalid Sopel plugin: %s' % filename)
sopel.plugins.exceptions.PluginError: Invalid Sopel plugin: /home/dgw/.sopel/plugins/bombbot.py
```

### Environment
- Sopel `.version`: 8b463a0e49cac7a27dc528a180243a6a5183d1f9
- Sopel installed via: `pip -e`
- Python version: 3.9.5
- Operating system: Ubuntu 20.04
- IRCd `/version`: n/a
- Relevant plugins: n/a

### Additional contract requirements

- Add a public function `_list_plugin_filenames(directory)` in the module `sopel.plugins`. It accepts a plugin directory as `str` or `os.PathLike` and yields `(name, absolute_path)` pairs for each entry that resolves to an existing file or package. Entries whose resolved real path does not exist (such as broken symlinks) are omitted, and a warning is logged when such an entry is skipped.


- For a file named `amazing_plugin.py`, the yielded name must be `amazing_plugin`.
