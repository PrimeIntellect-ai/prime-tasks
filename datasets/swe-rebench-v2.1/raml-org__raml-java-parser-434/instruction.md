Traits are not applied when having unimplemented optional methods with resourcePathName in type.
Given this raml:

```#%RAML 1.0
title: Test

traits:
  trait:
    queryParameters:
      param:
        required: false
        default: "Default value"

resourceTypes:
  optional-post:
    get:
      is: [ trait ]
    post?:
      body:
        application/json:
          type: <<resourcePathName>>

/unimplemented-post:
  type: optional-post
```

GET method of /unimplemented-post does not have queryParameter ```param```and it's default value.
