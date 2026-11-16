dict/objects in Fields need to be serialized as strings
It's not obvious from the docs at https://mana.mozilla.org/wiki/display/CLOUDSERVICES/Logging+Standard, but we don't support recursive fields in our logging standard (because protobuf does not support them). In the case where the app has such structured fields, we need them to be serialized as nested JSON strings, e.g.

    {..., "Fields":{"querystring": {"foo": "bar"}}}

should instead be serialized as:

    {..., "Fields":{"querystring": "{\"foo\": \"bar\"}"}}

The JSON schema is here: https://mana.mozilla.org/wiki/pages/viewpage.action?pageId=42895640
