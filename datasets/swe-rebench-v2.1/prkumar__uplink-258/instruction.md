Unexpected behavior of async `response_handler` callback
**Describe the bug**

Changes made in #248 break the async `response_handler` callback behavior.

**To Reproduce**

Define asynchronous response handler:

```python
@uplink.response_handler
async def custom_response_handler(response):
    return "result"
```

Define consumer method decorated this way:

```python
class ExampleConsumer(uplink.Consumer):
    @custom_response_handler
    @uplink.get("/")
    def consumer_method(self):
        pass
```

Call the method:

```python
async def main(base_url: str):
    async with aiohttp.ClientSession() as session:
        example_consumer = ExampleConsumer(
            base_url=base_url,
            client=uplink.AiohttpClient(session),
        )

        # expected: "result", actual: <coroutine object custom_response_handler at 0x7f7c7ccbc8c0>
        # In the `0.9.5`, asynchronous callbacks worked as expected
        result = await example_consumer.consumer_method()

        # double await works, but this is unexpected
        result = await (await example_consumer.consumer_method())
```

Since the `0.9.6`, awaited method call is a coroutine.

**Expected behavior**

A consumer method decorated this way returns a result using a single `await`.

**Additional context**

The `aiohttp` client is used.
