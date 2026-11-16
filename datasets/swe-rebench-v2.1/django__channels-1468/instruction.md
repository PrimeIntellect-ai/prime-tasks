get_handler_name allow call to private methods
Hi there !

## Environment:
- python3.8
- channels 2.4.0

## Bug:
Not sure if it's really a bug or an intended behaviour. But it seem that the function [get_handler_name](https://github.com/django/channels/blob/42070bfe400048d7c8efe551d37f7ac0d26d8e7e/channels/consumer.py#L12) behave quite strangely and allow the call of "private" methods in some corner cases.

Examples:

```python

channel_layer = get_channel_layer()

message = { "type": "_my_private_function", "data": "here some data" }
await channel_layer.group_send(response_data['id'], message=message)

# Will fail, raising ValueError("Malformed type in message (leading underscore)")
# from get_handler_name


message = { "type": ".my_private_function", "data": "here some data" }
await channel_layer.group_send(response_data['id'], message=message)

# Will work and call "_my_private_function" from consumer instance
```

## Expected Behavior:

Should either, allow to call `_private_methods` all the time (and not raise error in the first case).
Or never allow this kind of call and consider them invalid.

## Fix proposal:

[HIDDEN]

If this issue is validated as a "bug", I will happily open a PR.

Regards,
