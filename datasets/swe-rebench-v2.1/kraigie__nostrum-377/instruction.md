:GUILD_ROLE_CREATE and :GUILD_ROLE_UPDATE are not including the guild id in the events.
 :GUILD_ROLE_CREATE and :GUILD_ROLE_UPDATE are supposed to include the guild id as part of the event, but they are not. My best **guess** is that something as part of the pluggable guild cache change messed this up. [HIDDEN]

 See [here](https://github.com/Kraigie/nostrum/blob/168367916e2d890a1dcc6e19389ac2dbc9666e37/lib/nostrum/cache/guild_cache/ets.ex#L268)

If this is the correct change, id be happy to make a quick PR for it.

### Additional contract requirements

The return value from role creation and the return value from role updates in the guild cache must each include the guild ID supplied for that operation, together with the role data relevant to the operation. The GUILD_ROLE_CREATE and GUILD_ROLE_UPDATE events must each include their guild ID along with their role data. No particular container representation is required for these values.
