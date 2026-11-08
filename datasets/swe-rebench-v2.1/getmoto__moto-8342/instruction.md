IoT Data Shadow Delta with complex datastructure exposes jsondiff symbol and raises TypeError
I'm using Moto 5.0.21, and jsondiff 2.2.1.

When deleting items from a second-level list in an IoT data shadow, there's a `jsondiff.deleted` symbol exposed, and breaking the subsequent JSON parsing. [HIDDEN]

Pytest showing the issue:

```Python
from moto import mock_aws
import boto3


@mock_aws
def test_list():
    iot_client = boto3.client(service_name="iot", region_name="eu-central-1")
    iot_client.create_thing(thingName="example-thing")

    iot_data_client = boto3.client(service_name="iot-data", region_name="eu-central-1")

    iot_data_client.update_thing_shadow(
        thingName="example-thing",
        payload=json.dumps(
            {
                "state": {
                    "reported": {
                        "list": [
                            ["value_1"],
                            ["value_2"],
                        ]
                    }
                }
            }
        ),
    )
    iot_data_client.update_thing_shadow(
        thingName="example-thing",
        payload=json.dumps(
            {
                "state": {
                    "desired": {
                        "list": [
                            ["value_1"],
                        ]
                    }
                }
            }
        ),
    )

    iot_data_client.get_thing_shadow(thingName="example-thing")
    # throws TypeError: keys must be str, int, float, bool or None, not Symbol
```

Traceback:
```Python
venv/python-3.11.9/lib/python3.11/site-packages/botocore/client.py:565: in _api_call
    return self._make_api_call(operation_name, kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/client.py:1001: in _make_api_call
    http, parsed_response = self._make_request(
venv/python-3.11.9/lib/python3.11/site-packages/botocore/client.py:1027: in _make_request
    return self._endpoint.make_request(operation_model, request_dict)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/endpoint.py:119: in make_request
    return self._send_request(request_dict, operation_model)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/endpoint.py:202: in _send_request
    while self._needs_retry(
venv/python-3.11.9/lib/python3.11/site-packages/botocore/endpoint.py:354: in _needs_retry
    responses = self._event_emitter.emit(
venv/python-3.11.9/lib/python3.11/site-packages/botocore/hooks.py:412: in emit
    return self._emitter.emit(aliased_event_name, **kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/hooks.py:256: in emit
    return self._emit(event_name, kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/hooks.py:239: in _emit
    response = handler(**kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/retryhandler.py:207: in __call__
    if self._checker(**checker_kwargs):
venv/python-3.11.9/lib/python3.11/site-packages/botocore/retryhandler.py:284: in __call__
    should_retry = self._should_retry(
venv/python-3.11.9/lib/python3.11/site-packages/botocore/retryhandler.py:307: in _should_retry
    return self._checker(
venv/python-3.11.9/lib/python3.11/site-packages/botocore/retryhandler.py:363: in __call__
    checker_response = checker(
venv/python-3.11.9/lib/python3.11/site-packages/botocore/retryhandler.py:247: in __call__
    return self._check_caught_exception(
venv/python-3.11.9/lib/python3.11/site-packages/botocore/retryhandler.py:416: in _check_caught_exception
    raise caught_exception
venv/python-3.11.9/lib/python3.11/site-packages/botocore/endpoint.py:278: in _do_get_response
    responses = self._event_emitter.emit(event_name, request=request)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/hooks.py:412: in emit
    return self._emitter.emit(aliased_event_name, **kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/hooks.py:256: in emit
    return self._emit(event_name, kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/botocore/hooks.py:239: in _emit
    response = handler(**kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/moto/core/botocore_stubber.py:38: in __call__
    response = self.process_request(request)
venv/python-3.11.9/lib/python3.11/site-packages/moto/core/botocore_stubber.py:88: in process_request
    status, headers, body = method_to_execute(
venv/python-3.11.9/lib/python3.11/site-packages/moto/core/responses.py:291: in dispatch
    return cls()._dispatch(*args, **kwargs)
venv/python-3.11.9/lib/python3.11/site-packages/moto/core/responses.py:503: in _dispatch
    return self.call_action()
venv/python-3.11.9/lib/python3.11/site-packages/moto/core/responses.py:591: in call_action
    response = method()
venv/python-3.11.9/lib/python3.11/site-packages/moto/iotdata/responses.py:45: in get_thing_shadow
    return json.dumps(payload.to_dict())
/usr/local/lib/python3.11/json/__init__.py:231: in dumps
    return _default_encoder.encode(obj)
/usr/local/lib/python3.11/json/encoder.py:200: in encode
    chunks = self.iterencode(o, _one_shot=True)
```

Also, I'm not sure if AWS would even detect such an item deletion, or if it would just see the list as completely new. I don't have the resources accessible right now to test that.

### Additional contract requirements

- When the desired state and the reported state differ in a list value, the delta for that list is the complete desired list (the list exactly as it appears in the desired state).
- After a shadow update causes a nested-list deletion, calling `get_thing_shadow` must complete successfully. The returned delta must not expose `jsondiff` symbols and must be JSON-serializable.


- When a list in the desired state and the same list in the reported state have different values, the delta for that list must be the complete desired list, even when the two lists share no elements.
