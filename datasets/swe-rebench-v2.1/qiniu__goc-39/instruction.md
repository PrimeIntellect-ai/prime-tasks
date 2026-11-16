unable to build project [https://github.com/enricofoltran/simple-go-server]
Steps：
1. workspace and environment
```
➜  simple-go-server git:(master) echo $GOPATH
/Users/jicarl/k8s
➜  simple-go-server git:(master) pwd
/Users/jicarl/qbox/simple-go-server
➜  simple-go-server git:(master) git remote -v
origin	git@github.com:enricofoltran/simple-go-server.git (fetch)
origin	git@github.com:enricofoltran/simple-go-server.git (push)
➜  simple-go-server git:(master)
```
2. try to use goc command to build this project, but got errors:
```
➜  simple-go-server git:(master) goc build .
2020/05/24 15:15:29 cover.go:114: go list cmd is: [go list -json . ./...]
2020/05/24 15:15:29 tmpfolder.go:65: Temp project generated in: /var/folders/_6/t59gxn4d0zz12vqlm3j3gwhr0000gn/T/goc-055cb24d8755
2020/05/24 15:15:29 tmpfolder.go:78: New working/building directory in: /var/folders/_6/t59gxn4d0zz12vqlm3j3gwhr0000gn/T/goc-055cb24d8755/Users/jicarl/qbox/simple-go-server
2020/05/24 15:15:29 tmpfolder.go:47: New GOPATH: /var/folders/_6/t59gxn4d0zz12vqlm3j3gwhr0000gn/T/goc-055cb24d8755:/Users/jicarl/k8s
2020/05/24 15:15:29 cover.go:114: go list cmd is: [go list -json . ./...]
2020/05/24 15:15:29 build.go:61: Go building in temp...
2020/05/24 15:15:29 build.go:74: Fail to execute: go build .. The error is: chdir /var/folders/_6/t59gxn4d0zz12vqlm3j3gwhr0000gn/T/goc-055cb24d8755/Users/jicarl/qbox/simple-go-server: no such file or directory, the stdout/stderr is:
```

### Additional contract requirements

- `goc build .` must succeed for a legacy Go project located outside the configured GOPATH.
