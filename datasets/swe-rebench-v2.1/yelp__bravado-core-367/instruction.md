Validation fails for x-nullable objects that happen to have discriminator
Where a thing is defined as `x-nullable` and has a `discriminator` at the same time, `bravado-core@5.14.0` validation fails with a `TypeError` in case the instance resolves to `None`:

```
Traceback (most recent call last):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/falcon/api.py", line 286, in __call__
    process_response(req, resp, resource, req_succeeded)
  File "/Users/myself/project/.venv/kw/misc/openapi/validator.py", line 141, in process_response
    validate_response(resp_spec, operation, bravado_response)
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/response.py", line 175, in validate_response
    validate_response_body(op, response_spec, response)
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/response.py", line 214, in validate_response_body
    op.swagger_spec, response_body_spec, response_value,
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/validate.py", line 59, in validate_schema_object
    validate_object(swagger_spec, schema_object_spec, value)
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/validate.py", line 25, in scrubbed
    return func(*args, **kwargs)
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/validate.py", line 109, in validate_object
    ).validate(value)
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 347, in validate
    for error in self.iter_errors(*args, **kwargs):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 323, in iter_errors
    for error in errors:
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/_validators.py", line 315, in allOf
    for error in validator.descend(instance, subschema, schema_path=index):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 339, in descend
    for error in self.iter_errors(instance, schema):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 323, in iter_errors
    for error in errors:
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/swagger20_validator.py", line 234, in ref_validator
    for error in validator.descend(instance, resolved):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 339, in descend
    for error in self.iter_errors(instance, schema):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 323, in iter_errors
    for error in errors:
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/_validators.py", line 286, in properties
    schema_path=property,
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 339, in descend
    for error in self.iter_errors(instance, schema):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 323, in iter_errors
    for error in errors:
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/swagger20_validator.py", line 234, in ref_validator
    for error in validator.descend(instance, resolved):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 339, in descend
    for error in self.iter_errors(instance, schema):
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/jsonschema/validators.py", line 322, in iter_errors
    errors = validator(self, v, instance, _schema) or ()
  File "/Users/myself/project/.venv/.venv/lib/python3.7/site-packages/bravado_core/swagger20_validator.py", line 157, in discriminator_validator
    discriminator_value = instance[discriminator_attribute]
TypeError: 'NoneType' object is not subscriptable
```
This definitely should error out and instead validate A-OK in fact.

### Additional contract requirements

- When a `None` value is validated against a schema marked `x-nullable` that also has a discriminator, validation must accept the value rather than raise a `TypeError`.
