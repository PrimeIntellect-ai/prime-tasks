Wrong behavior with SET NX GET
According to Redis specification, if we specify NX with GET in a SET command, even if the condition for NX is not met and the value is not set, we still return the old value instead of returning a `nil`:

https://redis.io/commands/set/
```
[Null reply](https://redis.io/docs/reference/protocol-spec#resp-bulk-strings): (nil) if the SET operation was not performed because the user specified the NX or XX option but the condition was not met.

If the command is issued with the GET option, the above does not apply. It will instead reply as follows, regardless if the SET was actually performed:

[Bulk string reply](https://redis.io/docs/reference/protocol-spec#resp-bulk-strings): the old string value stored at key.

[Null reply](https://redis.io/docs/reference/protocol-spec#resp-bulk-strings): (nil) if the key did not exist.
```

However, it doesn't seem like the behavior is followed [here](https://github.com/alicebob/miniredis/blob/master/cmd_string.go#L134): [HIDDEN]
