Watchdog with automatic inbound flow control should start with WAITING state
There are 2 states in watchdog, IDLE and WAITING. IDLE indicates the stream is waiting for caller to take some action, and WAITING indicates the stream is waiting for server to return something. We update the state whenever there's some activity from the server or caller, and record timestamps when the state changes. When a stream is inactive for too long, watchdog will cancel the stream and throw an exception.

In the current implementation when we create a `WatchdogStream`, we always set the stream state to "IDLE". The "IDLE" state is flipped to "WAITING" state when caller calls `request()`. However, this implementation is assuming that automatic inbound flow control is disabled. In the case where automatic inbound flow control is enabled, caller won't call `request()` for the next response and in this case starting the `WatchdogStream` in the IDLE state is incorrect.

### Additional contract requirements

- When this timeout occurs before the next response, the exception message must contain `waiting for next response`.
