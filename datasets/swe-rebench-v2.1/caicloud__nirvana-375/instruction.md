`nirvana init` cannot be run outside GOPATH
<!-- Issue template; please answer the questions. -->

**Is this a BUG REPORT or FEATURE REQUEST?**:

/kind feature

**What happened**:

`nirvana init` cannot be run outside GOPATH:
```
$ nirvana init foo
FATAL 1027-18:47:01.921+08 init.go:50 | /tmp/foo is not in GOPATH
```

**What you expected to happen**:

`nirvana init` is able to create a project outside GOPATH.

**How to reproduce it (as minimally and precisely as possible)**:

run `nirvana init` outside GOPATH.

**Anything else we need to know?**:
