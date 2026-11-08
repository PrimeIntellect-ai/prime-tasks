Decoding to pointers with nil value
Mapstructure is very useful and great library, thank you!

But many gophers use pointer type for know whether value is absent, or whether not.
The problem that mapstructure could not properly decode map values into struct field that is pointer.

**Example:**
We have target struct

```go
type Result struct {
	T *time.Time
}
```

and have a decode hook, which try to parse *string* to **time.Time*

```go
func (f reflect.Type, t reflect.Type, data interface{}) (interface{}, error) {
	if t == reflect.TypeOf(&time.Time{}) && f.Kind() == reflect.String && data == "" {
		return nil, nil
	}

        ...

	return data, nil
}
```

After decoding
***I would like to expect***
```
type Result struct {
	T *time.Time // nil
}
```
***But I got***
```
type Result struct {
	T *time.Time // 0001-01-01 00:00:00 +0000 UTC
}
```

[HIDDEN]

### Additional contract requirements

- When a decode hook returns nil for input targeting an initially nil pointer field, and ZeroFields is false, decoding must leave that field nil.
