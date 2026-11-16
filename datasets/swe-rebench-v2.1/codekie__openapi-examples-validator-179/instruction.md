the "--no-additional-properties" flag is not working
It looks like the `--no-additional-properties` flag is not working as expected.

**Expected result:**
It should raise an error if an attribute is present in an example but not declared in schema.

**Actual result:**
No errors were found. The given example is considered valid.

**To reproduce the issue:**

> test-with-extra-property.json
```
{ "id": 123, "name": "Bob", "gender": "male" }
```


> openapi-spec.yml
```
swagger: "2.0"
info:
  version: 1.0.0
consumes:
  - application/json
produces:
  - application/json
paths:
  /user:
    get:
      responses:
        "200":
          schema:
            type: object
            properties:
              name:
                type: string
              id:
                type: integer
            required:
              - name
              - id
```

> command ran
```
yarn openapi-examples-validator \
--schema-jsonpath $.paths./user.get.responses.200.schema \
--example-filepath ./test-with-extra-property.json \
--no-additional-properties \
./openapi-spec.yml
```

> console output
```
Validating single external example
Schemas with examples found: 1
Examples without schema found: 0
Total examples found: 1

No errors found.
```

I would have expected the `gender` attribute to raise an error because it's not part of the API spec definition.


Let me know if you need more info or if I can help.
