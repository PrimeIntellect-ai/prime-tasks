Handle unavailable guilds in GUILD_CREATE
### Steps to reproduce

Join an unavailable guild

### Expected result

Torn between fully ignoring the event or calling `on_guild_delete` so it dispatches a `GuildUnavailableEvent`

### Actual result

![image](https://user-images.githubusercontent.com/29100934/170681523-0e007f2b-0b17-4bd1-9a9d-82cae1827be6.png)

### System info

```shell
hikari (2.0.0.dev109) [HEAD]
located at /home/davfsa/coding/hikari/.venv/lib/python3.10/site-packages/hikari
CPython 3.10.0 GCC 10.2.1 20210110
```


### Further info

_No response_

### Checklist

- [X] I have made sure to remove ANY sensitive information (bot token, passwords, credentials, personal details, etc.).
- [X] I have searched the issue tracker and have made sure it's not a duplicate. If it is a follow up of another issue, I have specified it.

### Additional contract requirements

When a `GUILD_CREATE` payload describes an unavailable guild (i.e. `unavailable` is
truthy), the event must not be treated as a normal guild creation: it must not be
deserialized or dispatched as a `GuildAvailableEvent` or a `GuildJoinEvent`, and the
guild must not be cached as an available guild. Either of the following outcomes is
acceptable:

- ignore the event entirely, or
- delegate to `on_guild_delete` so that a `GuildUnavailableEvent` is dispatched.
