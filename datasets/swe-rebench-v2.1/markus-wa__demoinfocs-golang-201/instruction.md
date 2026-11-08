another "no-panic" issue
I faced another debugging problem with new "no-panic" behaviour:
```go
var dummyInt int

p.RegisterEventHandler(func(e events.DataTablesParsed) {
	players := p.ServerClasses().FindByName("CCSPlayer")
	players.OnEntityCreated(func(playerEntity *st.Entity) {
		prop := playerEntity.FindPropertyI("m_bIsLookingAtWeapon")
		if prop != nil {
			prop.Bind(&dummyInt, st.ValTypeBoolInt)
		}
	})
})

err = p.ParseToEnd()
if err != nil {
	panic(err)
}
```

Since `dummyInt` is `int` and `st.ValTypeBoolInt` implies that it should be `bool`, we get this error at runtime with `v1.8.0` or newer:
```
panic: interface conversion: interface {} is *int, not *bool

goroutine 1 [running]:
main.main()
	C:/Users/admin/go/src/demoinfocs-test-cases/main.go:69 +0x1d5
```

where 69th line is, of cource, `panic(err)` so we cannot track down the issue exactly.

While with `v1.7.6` we got
```
panic: interface conversion: interface {} is *int, not *bool [recovered]
	panic: interface conversion: interface {} is *int, not *bool [recovered]
	panic: interface conversion: interface {} is *int, not *bool

goroutine 20 [running]:
github.com/markus-wa/godispatch.callConsumerCode.func1()
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/godispatch@v1.2.1/dispatch.go:104 +0x8f
panic(0x874c60, 0xc000d8c3c0)
	C:/Program Files/Go/src/runtime/panic.go:522 +0x1c3
github.com/markus-wa/demoinfocs-golang.recoverFromUnexpectedEOF(...)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/parsing.go:120
github.com/markus-wa/demoinfocs-golang.(*Parser).handlePacketEntities.func1(0xc000106000)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/entities.go:14 +0x139
panic(0x874c60, 0xc000d8c3c0)
	C:/Program Files/Go/src/runtime/panic.go:522 +0x1c3
github.com/markus-wa/demoinfocs-golang/sendtables.(*Property).Bind.func2(0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/sendtables/entity.go:372 +0x65
github.com/markus-wa/demoinfocs-golang/sendtables.(*Property).OnUpdate(...)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/sendtables/entity.go:341
github.com/markus-wa/demoinfocs-golang/sendtables.(*Property).Bind(0xc000bf25e0, 0x83d580, 0xc00006e120, 0x6)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/sendtables/entity.go:400 +0xb6
main.main.func1.1(0xc000058420)
	C:/Users/admin/go/src/demoinfocs-test-cases/main.go:62 +0x9e
github.com/markus-wa/demoinfocs-golang/sendtables.(*ServerClass).newEntity(0xc0004866e0, 0xc0003c8690, 0x1, 0x8800000000000000)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/sendtables/sendtables.go:120 +0x2f5
github.com/markus-wa/demoinfocs-golang/sendtables.(*SendTableParser).ReadEnterPVS(0xc0000fc150, 0xc0003c8690, 0x1, 0xd59be0)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/sendtables/st_parser.go:290 +0xcd
github.com/markus-wa/demoinfocs-golang.(*Parser).handlePacketEntities(0xc000106000, 0xc000888300)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/demoinfocs-golang@v1.7.6/entities.go:43 +0x26b
reflect.Value.call(0x84e0a0, 0xc0000644a0, 0x13, 0x8ea727, 0x4, 0xc000057f68, 0x1, 0x1, 0xc00008f470, 0x98afc0, ...)
	C:/Program Files/Go/src/reflect/value.go:447 +0x468
reflect.Value.Call(0x84e0a0, 0xc0000644a0, 0x13, 0xc000057f68, 0x1, 0x1, 0x6, 0xd38b20, 0xc000382000)
	C:/Program Files/Go/src/reflect/value.go:308 +0xab
github.com/markus-wa/godispatch.callConsumerCode(0x84e0a0, 0xc0000644a0, 0x13, 0xc000057f68, 0x1, 0x1)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/godispatch@v1.2.1/dispatch.go:107 +0x87
github.com/markus-wa/godispatch.(*Dispatcher).Dispatch(0xc000106020, 0x8d41e0, 0xc000888300)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/godispatch@v1.2.1/dispatch.go:93 +0x24e
github.com/markus-wa/godispatch.(*Dispatcher).dispatchQueue(0xc000106020, 0xc000058060)
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/godispatch@v1.2.1/dispatch.go:155 +0xfc
created by github.com/markus-wa/godispatch.(*Dispatcher).AddQueues
	C:/Users/admin/go/pkg/mod/github.com/markus-wa/godispatch@v1.2.1/dispatch.go:141 +0x158
```

which is much more informative 😃

### Additional contract requirements

A non-EOF panic encountered while parsing must propagate as a panic rather than be converted into an ordinary returned error.
