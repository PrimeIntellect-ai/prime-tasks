the stateless methods do not set basic auth
**What happened?**

```ts
import { createToken, checkToken } from "@octokit/oauth-app";

const result = await checkToken({
  clientId: process.env.CLIENT_ID,
  clientSecret: process.env.CLIENT_SECRET,
  token
});
```

This throws a 404 error, the `authorization` header is not set

**What did you expect to happen?**

The `authorization` header should be set to basic auth from the `clientId` and `clientSecret` options

**What the problem might be**

The stateless `checkToken` method does not set any auth

https://github.com/octokit/oauth-app.js/blob/b281913f359a8dd765564fdeb8786b0f7b4b30f3/src/methods/check-token.ts#L15-L28

### Additional contract requirements

- For stateless `checkToken` requests, the authorization header must be exactly `basic MDEyMzowMTIzc2VjcmV0` when `clientId` is `0123` and `clientSecret` is `0123secret`.
