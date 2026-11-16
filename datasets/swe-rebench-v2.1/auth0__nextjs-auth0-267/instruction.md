Logout Handler [HIDDEN] for Hint
On this line:

https://github.com/auth0/nextjs-auth0/blob/6f36586d7189959a67a6dc8f663a529de522ab7f/src/auth0-session/handlers/logout.ts#L33

The session cache is [HIDDEN] which is needed on line:

https://github.com/auth0/nextjs-auth0/blob/6f36586d7189959a67a6dc8f663a529de522ab7f/src/auth0-session/handlers/logout.ts#L47

### Additional contract requirements

- When performing distributed logout with the identity provider, the logout redirect must include the current session's ID token as the `id_token_hint`, while logout still clears the session.
