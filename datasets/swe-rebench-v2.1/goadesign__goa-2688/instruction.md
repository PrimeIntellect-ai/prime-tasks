Invalid indirect of type
Hi team,

I encountered an issue with using the `Required` DSL in `Payload` and `Body` in the design file. It generates the files fine but fails to compile. Received the following error:
```
gen/http/testapi/server/types.go:471:18: invalid indirect of body.name (type string)
```

```
Method("Test", func() {
		Payload(User)
                ...
		HTTP(func() {
			Body(User)
                        ......
	})

var User = func() {
	Attribute("name", ArrayOf(String, func() { Example("John") }))
	Required("name")
}
```
