Add support for embedded structs to document.NewFromStruct
```
type Embedded struct {
	Id string
}
type Example1 struct {
	*Embedded
}
type Example2 struct {
	Id string
}
```

`select * from examples where id = ?` will fail for the first struct but pass for the second struct - am i doing something wrong?
