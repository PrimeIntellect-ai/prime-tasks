ReadHeaderTimeout is setting a hard timeout on connections regardless of header sending
I think this setting is supposed to timeout connections that are not sending the headers and terminate them after this amount of time. However, I set the setting to 5 seconds, and the result is that all connections are terminated after 5 seconds, even if they correctly sent the headers. The connection starts up, but is then abruptly ended after the 5 seconds are passed.

[HIDDEN]

### Additional contract requirements

- If `ReadHeaderTimeout` is zero, use a default header timeout of 200 milliseconds; if it is negative, disable the header timeout.
- After a valid proxy header is received, expiry of the header timeout must not by itself terminate the established connection.
