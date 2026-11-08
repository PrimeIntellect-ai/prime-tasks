How to define properties of an object (that are referenced to definitions) as required ?
## Problem statement

The expected behaviour is that go-swagger defines required fields as pointers. For example,

```
SignupRequest:
    properties:
      email:
        type: string
    required:
      - email
```

will be

```
type SignupRequest struct {
	// email
	// Required: true
	Email *string `json:"email"`
}
```

However, required properties of an object that are referenced to definitions  are not pointers by default. For example:

```
SignupRequest:
    properties:
      email:
        $ref: "#/definitions/Email"
    required:
      - email
definitions:
  Email:
    type: string
```
wille be:

```
type SignupRequest struct {
	// email
	// Required: true
	Email Email `json:"email"`
}
```

Should Email field be of *Email type?

Now to get the email as pointer, we can use `x-nullable`. However the following does not work:

```
SignupRequest:
    properties:
      email:
        $ref: "#/definitions/Email"
        x-nullable: true
    required:
      - email
definitions:
  Email:
    type: string
```

But If we put `x-nullable` in the definition as following, it works, but I do not want to do it in the common definitions!

```
SignupRequest:
    properties:
      email:
        $ref: "#/definitions/Email"
    required:
      - email
definitions:
  Email:
    type: string
    x-nullable: true
```

The other workaround is to use `allOf` as following. Which is weird!

```
SignupRequest:
    properties:
      email:
        allOf:
          - $ref: "#/definitions/Email"
          - x-nullable: true
    required:
      - email
definitions:
  Email:
    type: string
```

## Environment
swagger version: 2.0
go version: go1.14.6

### Additional contract requirements

Required properties that reference a primitive definition are generated as pointers to the named definition type (for example, `*Email`). A property-level `x-nullable: true` on a reference must also make that property a pointer without changing the nullability behavior of the shared definition or other properties that reference it.
