Cannot install @master
Master seems to be broken and cannot build.

Using linux/amd64 with Go v1.17.4

Noticed when trying to update tools via vscode. Then replicated in command line:

Simply run:
```bash
go install github.com/go-delve/delve/cmd/dlv@master
```
and got as a result:
```
# github.com/go-delve/delve/service/dap
../../../go/pkg/mod/github.com/go-delve/delve@v1.7.4-0.20211207172355-a4ac69e87df3/service/dap/server.go:502:26: invalid type assertion: s.conn.(net.Conn) (non-interface type *connection on left)
```

Seems to be a compiler error.
