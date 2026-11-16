Non Required attributes with Default/Enum creating error
```
package design

var Storedload = ResultType("application/vnd.test", func() {
	TypeName("Storedload")

	Attributes(func() {
		Attribute("uploaded", Boolean, func() {
			Default(true)
		})
		//Required("uploaded")
	})

	View("default", func() {
		Attribute("uploaded")
	})

})
```
If I comment Required with Default value then it's creating below code. That has a type mismatch error.
```
{
		var zero bool
		if vres.Uploaded == zero {
			vres.Uploaded = true
		}
	}
```

### Additional contract requirements

When a non-required attribute with a default is mapped to a pointer-valued target field, the generated Go code must not have a type mismatch.
