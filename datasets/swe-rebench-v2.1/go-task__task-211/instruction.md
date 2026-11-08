Task directory: allow to create directory if missing
Hello,
consider the following taskfile:
```
tasks:
  build:
    dir: bin
    cmds: [[go build ../cmd/foo]]
```

The reason why I find it handy to specify `dir:` is because this will always put below `bin/` the OS-correct executable name.

If I where to fiddle with `go build -o`, I would have to do something like

```
tasks:
  build:
    cmds: [[go build -o bin/foo.{{exeExt}} ../cmd/foo]]
```
which is uglier, especially if I have multiple executables to build.

And now the problem: `bin` doesn't exist in the git source repo, so I have to add the classic `bin/.git_keepme` just to keep the directory existing.

To avoid the `.git_keepme`, one would have to make the command heavier with something like

```
tasks:
  build:
    cmds: [[mkdir -p bin && cd bin && go build ../cmd/foo]]
```

and this would still break on Windows because I think that `-p` is not supported.

I was thinking: what about adding a cousin of `dir:`, for example called `mkdir:` that creates the directory if it doesn't exist, or changing the `dir:` behavior to create the directory ?

Or am I missing something and there exist already an easy way to do what I want?

### Additional contract requirements

A task must be able to ensure that a directory it needs exists before its commands run, without depending on a shell-specific directory-creation command or a manually maintained placeholder. If the task is configured to run in that directory, its commands run there whether the directory existed beforehand or was created for that run.
