Panic in conn.bind
### Your environment.
  - Version: 1.3.4

### What happened?
Can't exactly reproduce this.

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x171c272]

goroutine 249 [running]:
github.com/pion/turn/internal/client.(*UDPConn).bind(0xc0007b6600, 0xc0006970e0, 0xc000a30200, 0x0)
	/go/pkg/mod/github.com/pion/turn@v1.3.4/internal/client/conn.go:525 +0x452
github.com/pion/turn/internal/client.(*UDPConn).WriteTo.func2.1(0xc0007b6600, 0xc0006970e0)
	/go/pkg/mod/github.com/pion/turn@v1.3.4/internal/client/conn.go:220 +0x39
created by github.com/pion/turn/internal/client.(*UDPConn).WriteTo.func2
	/go/pkg/mod/github.com/pion/turn@v1.3.4/internal/client/conn.go:219 +0xad
```

### Additional contract requirements

- When a TURN transaction fails during binding, the bind operation must return an error rather than panic.
