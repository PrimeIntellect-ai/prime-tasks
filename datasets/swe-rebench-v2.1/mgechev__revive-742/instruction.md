empty-lines false positive as of 1.2.2
Single line functions are flagged as having an erroneous newline at the start and end as of revive 1.2.2.

main.go:
```go
package main

func main() { println("foo") }
```

config.toml:
```toml
[rule.empty-lines]
```

```
@m4x3r:~/foo
$ go install github.com/mgechev/revive@v1.2.1

[19:54:35]
@m4x3r:~/foo
$ revive -config config.toml ./...

[19:54:39]
@m4x3r:~/foo
$ go install github.com/mgechev/revive@v1.2.2

[19:54:41]
@m4x3r:~/foo
$ revive -config config.toml ./...
main.go:3:13: extra empty line at the start of a block
main.go:3:13: extra empty line at the end of a block

[19:54:43]
@m4x3r:~/foo
$ go install github.com/mgechev/revive@v1.2.3

[19:54:46]
@m4x3r:~/foo
$ revive -config config.toml ./...
main.go:3:13: extra empty line at the start of a block
main.go:3:13: extra empty line at the end of a block
```
