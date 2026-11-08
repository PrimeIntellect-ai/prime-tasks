Feature: Allow broker creation in on_startup hook
For some reason, I need to delay the creation of an app's broker in an `on_startup` hook. This is mainly because my application has a pretty heavy warmup bootstrap that loads a lot of data into memory so I need to delay this bootstrap (which actually includes broker creation) after the parent process forked into worker subprocesses, otherwise the parent process has an unnecessary high memory footprint (that only worker processes need to have).

E.g.

```python
from faststream import FastStream
from faststream.kafka import KafkaBroker

app = FastStream()

@app.on_startup
def bootstrap():
    app.set_broker(KafkaBroker(["localhost:9092"]))
    # some warmup of the application pre-loading data into memory
    ...
```

For now, this isn't working because of this assert https://github.com/airtai/faststream/blob/9b7c33e8765485cf28f850cb485afcd838c12079/faststream/app.py#L40 [HIDDEN]

The example above is overly simplified and one could argue that broker could have been created outside the `bootstrap()` function, but, as per example at https://faststream.airt.ai/latest/getting-started/lifespan/hooks/#lifespan, it could be legitimate to create it based on environment setting specifying not only the broker host but also the kind of broker to use (nats, kafka, ...).

I currently solve the problem by providing an *empty* `KafkaBroker` at app instanciation (`app = FastStream(broker=KafkaBroker())`) before overriding it using `app.set_broker()` in the `bootstrap()` function.

However, as per the base `Application` constructor at https://github.com/airtai/faststream/blob/9b7c33e8765485cf28f850cb485afcd838c12079/faststream/_internal/application.py#L48-L70 which allows application instanciation without a defined broker and this comment in `Application.set_broker()` https://github.com/airtai/faststream/blob/9b7c33e8765485cf28f850cb485afcd838c12079/faststream/_internal/application.py#L117-L120 which claims to be used for creation/init in `on_startup`, I would have expected my use case to be legitimate.

[HIDDEN]

### Additional contract requirements

- An application created without a broker must be able to receive one through `set_broker` in an `on_startup` hook and run using that broker.
