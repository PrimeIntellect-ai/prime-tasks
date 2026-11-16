Log a debug message whenever `.emit` is called
Currently, emitted events are only logged if the user is listening to it.

This makes debugging hard as it requires a lot of listeners to be created to listen to individual events, to make this better we should change the emit function:

[HIDDEN]

To also send a debug event so that the event is always in the debugger logs.
Trigger a debug message periodically while the consumer is processing messages
This discussion:

https://github.com/bbc/sqs-consumer/discussions/381

Got me thinking that it would be useful if the consumer periodically sent a debug event while it was processing messages so that it could be verified that it is actually still working on processing those messages.

### Additional contract requirements

- The debug message emitted for each call to `.emit` must include the emitted event name.
- While a message handler is processing throughout a five-second interval, the consumer sends at least two debug messages during that interval.
