Weird error after bad producer initialization
Hi,
I'm getting this weird error after the GC tries to clean the memory and trigger the `__del__` method of `KafkaClient`. When the producer is not successfully initialized,  the property `_closed` is not ready in the `KafkaClient` object

this snippet if to illustrate the point:
```python
from kafka import KafkaProducer
import os
import gc

def test_bad_kafka_initialization():
    connect_str = os.getenv('BROKER_URL')
    try:
        producer = KafkaProducer(bootstrap_servers=connect_str)
    except Exception as e:
        gc.collect()
        assert isinstance(e, TypeError)
        raise e
```
if the `BROKER_URL` env variable is not defined is pretty normal raise a `TypeError` exception but after that, another ignored exception shows up :

```
Exception ignored in: <function KafkaClient.__del__ at 0x10ecc04c0>
Traceback (most recent call last):
  File "..../python3.8/site-packages/kafka/client_async.py", line 443, in __del__
  File "..../python3.8/site-packages/kafka/client_async.py", line 417, in _close
AttributeError: 'KafkaClient' object has no attribute '_closed'
```
[HIDDEN]

### Additional contract requirements

- Constructing a producer whose initialization fails (for example `KafkaProducer(bootstrap_servers=None)`, which raises `TypeError`) must still raise that original `TypeError` to the caller.
- After such a failed producer initialization, garbage collection of the partially constructed producer must not print or raise a secondary error from `KafkaClient.__del__` (such as the `AttributeError` about `_closed` shown above).
