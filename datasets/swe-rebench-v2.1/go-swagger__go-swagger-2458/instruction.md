custom tags are not added to instances of objects when specified
## Problem statement

I'm trying to use the `x-go-custom-tag` extension to add a tag to an object in my schema, but when a model is generated that has an instance of that object in it, the instance does not have any custom tags applied.

When applying the `x-go-custom-tag` as seen in the sample spec below, this is the code generated:
```
...

// ObjWithCustomTag obj with custom tag
//
// swagger:model ObjWithCustomTag
type ObjWithCustomTag struct {

    // custom tag
    CustomTag *ObjWithCustomTagCustomTag `json:"customTag,omitempty"`

}

...
```

### Expected Result
```
...

// ObjWithCustomTag obj with custom tag
//
// swagger:model ObjWithCustomTag
type ObjWithCustomTag struct {

    // custom tag
    CustomTag *ObjWithCustomTagCustomTag `json:"customTag,omitempty" myobjtag:"foo,bar"`

}

...
```

## Swagger specification

```
ObjWithCustomTag:
  type: object
  properties:
    customTag:
      type: object
      x-go-custom-tag: myobjtag:"foo,bar"
      properties:
        something:
          type: string
```

## Steps to reproduce

`swagger generate model -M ObjWithCustomTag -f spec.yml -t src/generated/`

## Environment
swagger version: 0.25.0
go version: 1.15.6
OS: macOS 11.0.1
