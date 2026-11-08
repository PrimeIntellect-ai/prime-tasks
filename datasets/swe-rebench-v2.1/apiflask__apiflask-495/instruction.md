Allow defining additional media types for a response
As mentioned in #492, it would be nice if APIFlask would provide an easier way to specify additional media types for a view's main response.

Currently the way to add additional media types is to use `app.doc(responses={})` but by doing so we need to provide the full OpenAPI definition for each response, including the main response (which we could define using `app.output()`). Ideally it should be possible to let APIFlask autogenerate the OpenAPI spec for the main response (_i.e._ the one specified with `app.output()`) and then let me merge in additional `responses.200.content.<my-media-type>` media types by using `app.doc()`.

The idea is to make it easier for APIs to perform [content negotiation](https://developer.mozilla.org/en-US/docs/Web/HTTP/Content_negotiation), while still enjoying automation in generating the OpenAPI description, as much as possible.

My main use case is being able to return either `JSON` or `HTML` from a view, while providing minimal detail to the `app.doc()` decorator.

I'm thinking something similar to what [fastAPI does](https://fastapi.tiangolo.com/advanced/additional-responses/#additional-media-types-for-the-main-response), where it is possible to have a main response's media type and then merge the relevant portion of the OpenAPI definition with additional media types. Something that would enable this type of usage:

```python
@app.get("/pets/<int:pet_id>")
@app.input(Accept, location="headers")
@app.output(PetOut)  # still have a main response of media type 'application/json'
@app.doc(responses={
    200: {
        'description': 'Return the resource in either JSON or HTML',
        'content': {
            'text/html': {}  # have an additional media type for the main response
        }
    }
})
def get_pet(pet_id, headers_data):
    pet = pets[pet_id]
    # depending on the content of the `Accept` header we may return JSON or HTML
    if "html" in headers_data.get('accept'):
        result = render_template('pets/pet-detail.j2.html', pet=pet)
    else:
        result = pet
    return result
```

This would be interpreted by APIFlask as:

- Use `@app.output` to define the relevant OpenAPI response with suitable media type and schema - in this case, it means adding the `application/json` media type with the `PetOut` schema
- Additionally, take my custom `@app.doc` and use it to add the additional HTML media type

The end result being something like this:

```yaml
paths:
    /pets/{pet_id}:
      get:
        responses:
          '200':
            content:
              text/html:
              application/json:
                schema:
                  $ref: '#/components/schemas/PetOut'
```

<!--
Replace this comment with a description of what the improvement should do.
Include details such as links to relevant specs or previous discussions.
-->

<!--
Replace this comment with an example of the problem which this change
would resolve or the ideal usage you suggested. Is this problem solvable
without changes to APIFlask, such as by subclassing or using an extension?
-->
