GuildThreadChannel.is_nsfw should be removed
This is just never supplied, a thread's nsfw state is implicitly inherited from the parent channel and never supplied on the thread object itself

Might also be worth refining this further, are we sure we can't just do [HIDDEN] for the channel models where its applicable and just leave it out for everything else

### Additional contract requirements

- `hikari.channels.GuildChannel` no longer accepts an `is_nsfw` argument.
- `hikari.channels.PermissibleGuildChannel` exposes an `is_nsfw` boolean attribute; when NSFW status is absent from channel data, the deserialized model reports `False`.
- For channel models where NSFW status applies, deserialization preserves a supplied NSFW value and uses `False` when that value is absent. Thread models do not expose `is_nsfw`.
