Req.cookies.getAll does not exist when using withMiddlewareAuthRequired on next@12
### Checklist

- [X] The issue can be reproduced in the [sample app](https://github.com/auth0-samples/auth0-nextjs-samples/tree/main/Sample-01) (or N/A).
- [X] I have looked into the [README](https://github.com/auth0/nextjs-auth0#readme) and have not found a suitable solution or answer.
- [X] I have looked into the [examples](https://github.com/auth0/nextjs-auth0/blob/main/EXAMPLES.md) and have not found a suitable solution or answer.
- [X] I have looked into the [API documentation](https://auth0.github.io/nextjs-auth0/) and have not found a suitable solution or answer.
- [X] I have searched the [issues](https://github.com/auth0/nextjs-auth0/issues) and have not found a suitable solution or answer.
- [X] I have searched the [Auth0 Community](https://community.auth0.com/c/sdks/5) forums and have not found a suitable solution or answer.
- [X] I agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Description

I tried to use the beta `withMiddlewareAuthRequired` on a `next@12.3.2` app but it throws regarding `req.cookies.getAll` does not exist. I noticed there is a somewhat similar issue (#892). I believe `req.cookies.getAll` is only available in `next@13` which is not mentioned in their documentation. It is not mentioned in the [migration guide from v1 to v2](https://github.com/auth0/nextjs-auth0/blob/vNext/V2_MIGRATION_GUIDE.md) of this library that it breaks compatibility with `next@12` though.

IMO the solution is to either bring back retro-compatibility or mention the breaking change in the migration documentation.

### Reproduction

I created a repro using the sample app that you can find here: https://github.com/auth0-samples/auth0-nextjs-samples/compare/main...Nargonath:auth0-nextjs-samples:cookies-getall-does-not-exist.

1. Clone the project locally.
2. Checkout the `cookies-getall-does-not-exist` branch.
3. Run `npm ci`.
4. Run `npm run dev`.
5. Execute:
```curl
curl --location --request GET 'http://localhost:3000/api/protected' \
--header 'Cookie: Cookie_1=value'
```
6. Notice the error:
![image](https://user-images.githubusercontent.com/583657/200533144-39ad60e0-5790-4ee7-884a-fe4ec9258fdb.png)


### SDK version

2.0.0-beta.2

### Next.js version

12.3.2

### Node.js version

16.15.1

### Additional contract requirements

- The fix must restore backward compatibility at runtime. `MiddlewareCookies.getAll(req)` must return the request cookies as a `Record<string, string>` even when `req.cookies` does not expose a `getAll` method (Next.js < 13.0.1, where edge cookies are exposed as a `Map`). Documenting the breaking change alone is not sufficient.
