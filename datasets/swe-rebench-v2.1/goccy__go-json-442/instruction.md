Marshal panic
Hi, every one!
   The go-json is a great project but just unstable and painc in some cases.

This problem can be reproduced with the following code:

```go
package main

import (
    "fmt"

    "github.com/goccy/go-json"
)

type UserTypeReq struct {
    UserType string `json:"user_type,omitempty"`
}

type Path struct {
    OrgID       *int `json:"org_id,omitempty"`  //
    UserTypeReq                                 // HERE IF CHAGE FIELD POSITION, MARSHAL IS WORKING OK.
    UserID      int  `json:"user_id,omitempty"` //
}

func main() {
    var route = Path{}

    var bytesJson, err = json.Marshal(route)
    if err != nil {
        fmt.Println(err)
    }
    fmt.Println(string(bytesJson))
}
```

Panic information:
```text
panic: runtime error: invalid memory address or nil pointer dereference
[signal 0xc0000005 code=0x0 addr=0x0 pc=0xc0e19c]

goroutine 1 [running]:
github.com/goccy/go-json/internal/encoder/vm.Run(0xc000094340, {0xc0000f6000?, 0x0?, 0x0?}, 0x0?)
        D:/Work/GOPATH/pkg/mod/github.com/goccy/go-json@v0.10.1/internal/encoder/vm/vm.go:26 +0x7c
github.com/goccy/go-json.encodeRunCode(0xc0000c9e38?, {0xc0000f6000?, 0xdc2160?, 0xc0000f8000?}, 0xc0000f6400?)
        D:/Work/GOPATH/pkg/mod/github.com/goccy/go-json@v0.10.1/encode.go:310 +0x68
github.com/goccy/go-json.encode(0xc000094340, {0xc51840, 0xc0000a03e0})
        D:/Work/GOPATH/pkg/mod/github.com/goccy/go-json@v0.10.1/encode.go:235 +0x21f
github.com/goccy/go-json.marshal({0xc51840, 0xc0000a03e0}, {0x0, 0x0, 0xc0000c9f50?})
        D:/Work/GOPATH/pkg/mod/github.com/goccy/go-json@v0.10.1/encode.go:150 +0xb9
github.com/goccy/go-json.MarshalWithOption(...)
        D:/Work/GOPATH/pkg/mod/github.com/goccy/go-json@v0.10.1/json.go:186
github.com/goccy/go-json.Marshal({0xc51840?, 0xc0000a03e0?})
        D:/Work/GOPATH/pkg/mod/github.com/goccy/go-json@v0.10.1/json.go:171 +0x2a
main.main()
        D:/Temp/go-json-err/main.go:22 +0x45
```
