unmarshal bug in 4.7.(0|1)
I've confirmed that we don't get the following error when i downgrade from 4.7.0 (or 4.7.1) to 4.6.1.

```
======================================================================
1) ERROR: test_bundles (bundles.test_bundles.BundlesTest)
----------------------------------------------------------------------
   Traceback (most recent call last):
    test/api/bundles/test_bundles.py line 30 in test_bundles
      app = self.client.Applications.Create(body=dict(name='test_app')).result()
    /usr/local/lib/python2.7/dist-packages/bravado/http_future.py line 77 in result
      self.response_callbacks)
    /usr/local/lib/python2.7/dist-packages/bravado/http_future.py line 115 in unmarshal_response
      operation)
    /usr/local/lib/python2.7/dist-packages/bravado_core/response.py line 112 in unmarshal_response
      op.swagger_spec, content_spec, content_value)
    /usr/local/lib/python2.7/dist-packages/bravado_core/unmarshal.py line 56 in unmarshal_schema_object
      return unmarshal_model(swagger_spec, schema_object_spec, value)
    /usr/local/lib/python2.7/dist-packages/bravado_core/unmarshal.py line 194 in unmarshal_model
      model_as_dict = unmarshal_object(swagger_spec, model_spec, model_value)
    /usr/local/lib/python2.7/dist-packages/bravado_core/unmarshal.py line 136 in unmarshal_object
      if schema.has_default(swagger_spec, prop_spec):
    /usr/local/lib/python2.7/dist-packages/bravado_core/schema.py line 22 in has_default
      return 'default' in swagger_spec.deref(schema_object_spec)
   TypeError: argument of type 'NoneType' is not iterable

```
