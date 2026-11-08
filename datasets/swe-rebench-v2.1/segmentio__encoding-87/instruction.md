json: Go 1.16 allows for ; in json tags
https://golang.org/doc/go1.16#encoding/json

```
package main

import (
	"encoding/json"
	"fmt"

	sjson "github.com/segmentio/encoding/json"
)

type S struct {
	F string `json:"a;b"`
}

func main() {
	data := []byte(`{"a;b": "hello"}`)

	var s1 S
	err1 := json.Unmarshal(data, &s1)
	fmt.Printf("stdlib: err=%s s=%s\n", err1, s1)

	var s2 S
	err2 := sjson.Unmarshal(data, &s2)
	fmt.Printf("segment: err=%s s=%s\n", err2, s2)

	if err1 != err2 {
		panic("err mismatch")
	}
	if s1 != s2 {
		panic("value mismatch")
	}
}
```
https://play.golang.com/p/l3RoNt3FYnB

```
~/tmp$ go version && go run main.go
go version go1.16.2 linux/amd64
stdlib: err=%!s(<nil>) s={hello}
segment: err=%!s(<nil>) s={}
panic: value mismatch

goroutine 1 [running]:
main.main()
	/home/thomas/tmp/main.go:29 +0x389
exit status 2
~/tmp$ go1.15 version && go1.15 run main.go
go version go1.15.10 linux/amd64
stdlib: err=%!s(<nil>) s={}
segment: err=%!s(<nil>) s={}
```
