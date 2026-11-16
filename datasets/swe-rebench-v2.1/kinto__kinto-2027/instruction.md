Crash with "in <string>' requires string as left operand, not int"
```
ValidationError: 'minVersion' is a required property

Failed validating 'required' in schema['properties']['versionRange']['items']['properties']['targetApplication']['items']:
    {'additionalProperties': False,
     'description': 'Target application',
     'properties': {'guid': {'description': 'The application unique '
                                            'identifier.',
                             'enum': ['{ec8030f7-c20a-464f-9b0e-13a3a9e97384}',
                                      '{3550f703-e582-4d05-9a08-453d09bdfdc6}',
                                      '{92650c4d-4b8e-4d2a-b7eb-24ecf4f6b63a}',
                                      '{aa3c5121-dab2-40e2-81ca-7ea25febc110}'],
                             'enumNames': ['Firefox',
                                           'Thunderbird',
                                           'Seamonkey',
                                           'Android'],
                             'title': 'Application id',
                             'type': 'string'},
                    'maxVersion': {'$ref': '#/definitions/maxVersion'},
                    'minVersion': {'$ref': '#/definitions/minVersion'}},
     'required': ['guid', 'minVersion', 'maxVersion'],
     'title': 'Target application',
     'type': 'object'}

On instance['versionRange'][0]['targetApplication'][0]:
    {'guid': 'ec8030f7-c20a-464f-9b0e-13a3a9e97384', 'maxVersion': '57.0.*'}
  File "kinto/views/records.py", line 73, in process_record
    jsonschema.validate(data, schema)
  File "jsonschema/validators.py", line 541, in validate
    cls(schema, *args, **kwargs).validate(instance)
  File "jsonschema/validators.py", line 130, in validate
    raise error

TypeError: 'in <string>' requires string as left operand, not int
(11 additional frame(s) were not displayed)
...
  File "cornice/service.py", line 494, in wrapper
    response = view_()
  File "kinto/core/resource/__init__.py", line 463, in put
    new_record = self.process_record(post_record, old=existing)
  File "kinto/views/records.py", line 81, in process_record
    raise_invalid(self.request, name=field, description=e.message)
  File "kinto/core/errors.py", line 178, in raise_invalid
    response = json_error_handler(request)
  File "kinto/core/errors.py", line 149, in json_error_handler
    [HIDDEN]
```

### Additional contract requirements

- When schema validation fails and an error name or path component is an integer, the failure must be reported as a validation error rather than causing a `TypeError` while formatting the error.
