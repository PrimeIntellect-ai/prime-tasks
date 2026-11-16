KafkaProducer hangs in busy loop after delivery timeout
After producing one message and after the delivery timeout expires, the producer thread seems to be hanging in a busy loop. This requires unnecessary CPU cycles. Did I something wrong in the configuration?

```python
import logging
import sys
import time
from datetime import timedelta

import kafka  # kafka-python 2.2.4

logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)
logging.getLogger('kafka').setLevel(logging.DEBUG)


def main():
    delivery_timeout = timedelta(seconds=2)

    producer = kafka.KafkaProducer(
        bootstrap_servers="localhost:9092",
        request_timeout_ms=int(delivery_timeout.total_seconds() * 1000 / 2),
        delivery_timeout_ms=int(delivery_timeout.total_seconds() * 1000),
    )

    # at least one message must be produced to trigger the issue
    producer.send("demo",  b"message")

    # simulate time without producing messages
    # after delivery_timeout_ms the poll() hangs in a busy loop
    time.sleep(delivery_timeout.total_seconds() + 1)


if __name__ == '__main__':
    main()
```

[kafka.log](https://github.com/user-attachments/files/20101919/kafka.log)
