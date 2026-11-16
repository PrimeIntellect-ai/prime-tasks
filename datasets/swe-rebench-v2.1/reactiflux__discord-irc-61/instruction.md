No way to login with a token
There currently doesn't appear to be a way to login to discord with a token on an API application account. :/

### Additional contract requirements

- The bot must be able to authenticate to Discord on an API application account using a token supplied in the bot configuration under the key `discordToken`.
- When a bot connects, it logs in to Discord with the configured `discordToken` value; the login must use exactly that value.
