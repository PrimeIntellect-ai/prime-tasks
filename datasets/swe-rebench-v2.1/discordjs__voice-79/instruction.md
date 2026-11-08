Allow the other side of the voice adapter to signal that it has been destroyed
If the producer of a voice adapter realises that the voice adapter can no longer be used (e.g. shard has been disconnected), it is currently unable to relay this information to @discordjs/voice.

In this situation, the producer should be able to signal to the library that the adapter can no longer be used, and the library should destroy the voice connection. When it is possible to recreate the voice adapter, the user can then recreate the voice connection.

### Additional contract requirements

The library-methods object provided to an adapter creator must expose a `destroy()` callback. Calling it signals that the adapter can no longer be used; the associated voice connection must become destroyed without sending a payload through that unusable adapter. Afterward, the user must be able to create a replacement voice connection when an adapter is available again.
