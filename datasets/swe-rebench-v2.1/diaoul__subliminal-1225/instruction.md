Add an option to save log to file
The current solution (on Linux) to keep logs of subliminal outputs is with:

```bash
subliminal --debug download -l en video.mkv > subliminal.log
```
It would be better (and it would work cross-platform) to add an option to the CLI.

### Additional contract requirements

- The CLI accepts a `--logfile` option. When it is given a path, subliminal writes its
  log output to that file (appending if the file already exists).
