cannot build if go.mod has relative path 'replace' directive
项目比较大，各种依赖很复杂，有十几个文件，之前都是用makefile编译的
执行goc build .报错
go: $path/$module@v0.0.0-20200804122736-5634267498a2: parsing $path/go.mod: open $path/go.mod: no such file or directory
FATA Fail to build: fail to execute: [/bin/bash -c go build  -o $path/$program .], err: exit status 1
试了下用go build .可以成功编译

### Additional contract requirements

- `goc build` should work for Go module projects that use relative local `replace` directives. These dependencies must resolve relative to the original project directory, rather than to the temporary build copy.
