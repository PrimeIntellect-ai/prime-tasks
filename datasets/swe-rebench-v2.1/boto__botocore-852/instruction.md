Unable to use non-string header values with Signature Version 4
When using S3 Signature Version 4 it's not possible to use non-string values in headers, such as Content-Length (which expects a integer/long). When passing a non-string value the following exception will be raised: ```AttributeError: 'int' object has no attribute 'strip'```.

Execute script as found on https://gist.github.com/steynovich/bbfe3057ba8ef89bb30d

Error:
```bash
$ ./upload.py
Traceback (most recent call last):
  File "./upload.py", line 25, in <module>
    ContentLength=size)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/client.py", line 310, in _api_call
    return self._make_api_call(operation_name, kwargs)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/client.py", line 396, in _make_api_call
    operation_model, request_dict)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/endpoint.py", line 111, in make_request
    return self._send_request(request_dict, operation_model)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/endpoint.py", line 136, in _send_request
    request = self.create_request(request_dict, operation_model)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/endpoint.py", line 120, in create_request
    operation_name=operation_model.name)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/hooks.py", line 226, in emit
    return self._emit(event_name, kwargs)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/hooks.py", line 209, in _emit
    response = handler(**kwargs)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/signers.py", line 84, in handler
    return self.sign(operation_name, request)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/signers.py", line 119, in sign
    signer.add_auth(request=request)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/auth.py", line 315, in add_auth
    canonical_request = self.canonical_request(request)
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/auth.py", line 257, in canonical_request
    cr.append(self.canonical_headers(headers_to_sign) + '\n')
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/auth.py", line 224, in canonical_headers
    sorted(headers_to_sign.get_all(key)))
  File "/Users/steynovich/.virtualenvs/uploadtest/lib/python2.7/site-packages/botocore/auth.py", line 223, in <genexpr>
    value = ','.join(v.strip() for v in
AttributeError: 'int' object has no attribute 'strip'
```

Expected behaviour: successful upload. You can test this by disabling the ContentLength parameter when executing upload_part() in the test script.

Used versions:
Python 2.7.10
boto3 (1.2.3)
botocore (1.3.25)
