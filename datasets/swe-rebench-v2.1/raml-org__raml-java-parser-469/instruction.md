Raml parser validates additionalProperties before the base properties
Raml parser validates additional properties before the base ones.
This causes the following example fails:

```
#%RAML 1.0
title: API

types:
  mytype:
      type: object
      properties:
        //: string
        attr: string
      example:
        attr: "a"
```

Base properties should be processed before the additional ones
