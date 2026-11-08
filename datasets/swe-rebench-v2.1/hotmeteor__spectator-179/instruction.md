[Feature] Expected empty response body
I'm writing some guides for a few similar tools and have set up similar test cases for each, so I've noticed a few missing things.

https://github.com/mkon/openapi_contracts/ will let you know if you've expected an empty response but a response is provided,

```
1) widgets POST /widgets responds with 201 when valid
    Failure/Error: expect(response).to match_openapi_doc(OPENAPI_DOC)
      * Expected empty response body
    # ./spec/requests/widgets_spec.rb:17:in `block (3 levels) in <top (required)>'
```

Basically if OpenAPI says this:

```

post:
  summary: Create Widget
  operationId: create-widget
  requestBody:
    description: Widget to create
    required: true
    content:
      application/json:
        schema:
          $ref: "../components/schema/widget.yaml"
  responses:
    '201':
      description: Created
```

and i've not actually defined a body, then if Spectator notices a body come back at all it should fail the test. I can then chose to define it in OpenAPI, or change the code.
