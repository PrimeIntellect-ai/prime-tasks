--choose doesnt recognize modules
```just
#!/usr/bin/env -S just --justfile

mod dev "just/dev.just"

set shell := ["bash", "-uc"]

default:
  @just --choose --justfile {{justfile()}}
```

```shell
just
```

modules in a justfile are not shown by the chooser
