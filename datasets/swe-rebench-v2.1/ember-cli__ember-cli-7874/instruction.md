Add environment output when building
Hi, I would love to see what environment I'm building for when I run `ember b` or in general any script that will trigger run for me.

Something like this
```bash
user@bash>ember b
Building
Environment: development
.....
```

### Additional contract requirements

- Both one-off builds and watch builds must announce their target environment with a line in the form `Environment: <environment>`.
