Exclude If doesn't work on boolean and nil parametr
- [x] I have looked at the documentation [here](https://pkg.go.dev/github.com/go-playground/validator/v10#section-documentation) first? Yes
- [x] I have looked at the examples provided that may showcase my question [here](/_examples)? Yes in doc.go too

### Package version eg. v9, v10:

v10

### Issue, Question or Enhancement:

exclude_if doesn't work with 'nil','true','false' values in provided parametrs

Examples:

	// exclude the field if the Field1 is equal to the parameter given:
	Usage: excluded_if=Field1 foobar

	// exclude the field if the Field1 and Field2 is equal to the value respectively:
	Usage: excluded_if=Field1 foo Field2 bar

### Code sample, to showcase or reproduce:

```go
type Struct1 struct {
  Field1 bool
  Field2 *string `validate:"excluded_if=Field1 false"`
}

type Struct2 struct {
  Field1 bool
  Field2 *string `validate:"excluded_if=!Field1"`
}

func main() {
ctx := context.Background()

  vldtr := validator.New()
str := "321321"
vldtr.StructCtx(ctx,Struct1{false, str})

vldtr.StructCtx(ctx, Struct2{false, str})
}

// Output: !panic recovered: Bad field type *int64
```
### Output

### Additional contract requirements

When `excluded_if` compares a boolean field, the parameters `true` and `false` match the corresponding boolean values. When it compares a pointer field, the parameter `nil` matches a nil pointer.
