IoT Data: delta calculation when desired state adds a new key
Hello, thank you very much for working on the IoT Data and shadow emulation. Really appreciate that you are fixing & improving things in this area.

After updating to 5.0.23, I noticed some of my tests failing, I assume due to #8342. On closer inspection, I guess the behaviour wasn't quite correct before either, but fails more loudly now. :) Basically, delta is not emitted correctly when a key is present in desired and absent in reported.

Test script:

```python
import json
import os

import boto3
import moto

os.environ.pop('AWS_PROFILE', None)
os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
os.environ['AWS_SESSION_TOKEN'] = 'testing'
os.environ['AWS_SECURITY_TOKEN'] = 'testing'
os.environ['AWS_DEFAULT_REGION'] = 'ca-central-1'


with moto.mock_aws():
    session = boto3.Session()
    iot = session.client('iot')
    iot_data = session.client('iot-data')

    thing_name = 'test'

    iot.create_thing(thingName=thing_name)

    payload = {
        'state': {
            'desired': {
                'new_key': True,
                'existing_key': True
            },
            'reported': {
                'existing_key': True
            }
        }
    }

    iot_data.update_thing_shadow(thingName=thing_name, payload=json.dumps(payload))

    response = iot_data.get_thing_shadow(thingName=thing_name)
    state = json.load(response['payload'])['state']

    print(json.dumps(state, indent=2))
```

Expected output:

```json
{
  "desired": {
    "new_key": true
  },
  "reported": {
    "existing_key": true
  },
  "delta": {
    "new_key": true
  }
}
```

Output with 5.0.21 (missing `delta`):

```json
{
  "desired": {
    "new_key": true
  },
  "reported": {
    "existing_key": true
  }
}
```

Output with 5.0.22 and 5.0.23:

```
Traceback (most recent call last):
  File "test.py", line 37, in <module>
    response = iot_data.get_thing_shadow(thingName=thing_name)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
[...]
TypeError: keys must be str, int, float, bool or None, not Symbol
```

In terms of your test suite, I guess the test cases might be something like this (completely untested):

```python
        (
            {"desired": {"enabled": True}},
            {"desired": {"enabled": True}, "delta": {"enabled": True}},
            {"reported": {}},
            {"desired": {"enabled": True}, "delta": {"enabled": True}}
        ),
        (
            {"desired": {"enabled": True}},
            {"desired": {"enabled": True}, "delta": {"enabled": True}},
            {"reported": {"online": True}},
            {"desired": {"enabled": True}, "reported": {"online": True}, "delta": {"enabled": True}}
        )
```

Thank you!
