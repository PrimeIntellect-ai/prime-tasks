slack bot should reply in thread
when the event is from a message in a thread, sendText should send to the thread, not to the channel

### Additional contract requirements

- When an incoming Slack message has a `thread_ts`, send the reply in that same thread by using that value as the reply’s `thread_ts`, rather than posting it as a channel-level message.
