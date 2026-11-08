model.conf has grammatical errors Enforce func return err is nil

## demo code
main.go

``` go
package main

import (
	"log"
	"net/http"

	"github.com/casbin/casbin/v2"
)

func main() {
	e, err := casbin.NewEnforcer("model.conf", "policy.csv")
	if err != nil {
		log.Fatal(err)
	}
	e.EnableLog(true)
	ok, err := e.Enforce("admin", "/v1/admin/manager/1", http.MethodPut)
	if err != nil {
		log.Fatal(err)
	}
	log.Println(ok)
}
```

model.conf

```env
[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = g(r.sub, p.sub) && keyMatch2(r.obj == p.obj) && regexMatch(r.act == p.act)
```

policy.csv

``` csv
p, common, /v1/admin/manager/:id, PUT
g, admin, common
```

casbin use version: `v2.2.1` [demo](https://github.com/zeromake/casbin-demo/tree/master)
``` bash
$ go run .\main.go
2020/03/18 16:35:24 false
```
switch casbin version: `v2.1.2`  [demo](https://github.com/zeromake/casbin-demo/tree/v2.1.2)
```bash
$ go run .\main.go
panic: interface conversion: interface {} is bool, not string

goroutine 1 [running]:
github.com/Knetic/govaluate.makeFunctionStage.func1(0x0, 0x0, 0x707f80, 0xa47ac7, 0x7ee3e0, 0xc000044ed0, 0x0, 0x0, 0x4a, 0xc0000505a0)
        C:/Users/coolz/go/pkg/mod/github.com/!knetic/govaluate@v3.0.1-0.20171022003610-9aa49832a739+incompatible/evaluationStage.go:245 +0x106
github.com/Knetic/govaluate.EvaluableExpression.evaluateStage(0x784bde, 0x22, 0x1, 0xc0000ce000, 0x14, 0x20, 0xc000050820, 0xc0000142d0, 0x4a, 0xc0000507d0, ...)
        C:/Users/coolz/go/pkg/mod/github.com/!knetic/govaluate@v3.0.1-0.20171022003610-9aa49832a739+incompatible/EvaluableExpression.go:205 +0x451
github.com/Knetic/govaluate.EvaluableExpression.evaluateStage(0x784bde, 0x22, 0x1, 0xc0000ce000, 0x14, 0x20, 0xc000050820, 0xc0000142d0, 0x4a, 0xc000050820, ...)
        C:/Users/coolz/go/pkg/mod/github.com/!knetic/govaluate@v3.0.1-0.20171022003610-9aa49832a739+incompatible/EvaluableExpression.go:172 +0x6b4
github.com/Knetic/govaluate.EvaluableExpression.Eval(0x784bde, 0x22, 0x1, 0xc0000ce000, 0x14, 0x20, 0xc000050820, 0xc0000142d0, 0x4a, 0x7eec60, ...)
        C:/Users/coolz/go/pkg/mod/github.com/!knetic/govaluate@v3.0.1-0.20171022003610-9aa49832a739+incompatible/EvaluableExpression.go:163 +0xc0
github.com/casbin/casbin/v2.(*Enforcer).enforce(0xc0000ba000, 0x0, 0x0, 0xc000065650, 0x3, 0x3, 0x44431e, 0x9db720, 0xc00003ff78)
        C:/Users/coolz/go/pkg/mod/github.com/casbin/casbin/v2@v2.1.2/enforcer.go:406 +0xae6
github.com/casbin/casbin/v2.(*Enforcer).Enforce(...)
        C:/Users/coolz/go/pkg/mod/github.com/casbin/casbin/v2@v2.1.2/enforcer.go:495
        D:/project/casbin-demo/main.go:16 +0x173
```

on enforcer.go#L350 `fmt.Errorf("panic: %v", err)` not log

https://github.com/casbin/casbin/blob/53116d0ba1f07f0277b06a471922180977bc062c/enforcer.go#L350

### Additional contract requirements

- Calls to `keyMatch2` and `regexMatch` with an argument count other than two, or with either argument not a string, must return an error rather than panic.
- When `Enforce` evaluates a malformed matcher call, it must return a non-nil error to its caller; it must not return nil error or allow a panic to escape.
