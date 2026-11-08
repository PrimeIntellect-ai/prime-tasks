support non-default /site-packages/
### Describe the feature

Like `pip freeze --path=<...>` allows so that packages installed from an old version of Python are supported.

### Additional contract requirements

Package discovery must include installed distributions found in an explicitly supplied site-packages location, even when that location is outside the active interpreter's default search paths. The command-line interface must accept `--path <directory>` to request package discovery from that alternate location and show the discovered packages in its output.
