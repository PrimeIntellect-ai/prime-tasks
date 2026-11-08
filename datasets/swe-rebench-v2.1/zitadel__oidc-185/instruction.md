missing state in redirect of implicit flow
**Describe the bug**

as described here: https://discord.com/channels/927474939156643850/927866013545025566/981120399658082334

> if I create the default quickstart react app, and using either Zitadel v1, or v2, setup a client to allow id_token, then configure the app to use id_token response type instead of code, the app doesn't work because the redirect from Zitadel doesn't include the state that the client

**Expected behaviour**

The redirect should include the state field.
