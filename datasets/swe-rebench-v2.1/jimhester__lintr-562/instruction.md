readLines warning for incomplete final line
Found in many packages, e.g. `nsprcomp`:

```
tmp = tempfile()
download.file('https://raw.githubusercontent.com/cran/nsprcomp/master/R/asdev.R', tmp)
lintr::lint(tmp)
# incomplete final line found on '/tmp/RtmptJEp8r/file3fb841ddb96d'
```

[HIDDEN] This is easy enough to fix; filing the issue first, since this might be considered a lint as well.

### Additional contract requirements

When `get_source_expressions` reads a file that lacks a terminal newline, it must not emit the incomplete-final-line warning.
