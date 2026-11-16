Modify session in getServerSideProps with getAccessToken
### Checklist

- [X] The issue can be reproduced in the [sample app](https://github.com/auth0-samples/auth0-nextjs-samples/tree/main/Sample-01) (or N/A).
- [X] I have looked into the [README](https://github.com/auth0/nextjs-auth0#readme) and have not found a suitable solution or answer.
- [X] I have looked into the [examples](https://github.com/auth0/nextjs-auth0/blob/main/EXAMPLES.md) and have not found a suitable solution or answer.
- [X] I have looked into the [API documentation](https://auth0.github.io/nextjs-auth0/) and have not found a suitable solution or answer.
- [X] I have searched the [issues](https://github.com/auth0/nextjs-auth0/issues) and have not found a suitable solution or answer.
- [X] I have searched the [Auth0 Community](https://community.auth0.com/c/sdks/5) forums and have not found a suitable solution or answer.
- [X] I agree to the terms within the [Auth0 Code of Conduct](https://github.com/auth0/open-source-template/blob/master/CODE-OF-CONDUCT.md).

### Description

When I try to modify the session in getServerSideProps it works fine.

```
export const getServerSideProps = withPageAuthRequired({
  returnTo: '/',
  async getServerSideProps(ctx) {
    const session = getSession(ctx.req, ctx.res);
    if (session) {
      session.test = 'Hello World';
    }
    return { props: {} };
  },
});

```

But when I want to get a new access token via `getAccessToken` function and modify the session with `afterRefresh` method it does not work.

```
 export const getServerSideProps = withPageAuthRequired({
  returnTo: '/',
  async getServerSideProps(ctx) {
    await getAccessToken(ctx.req, ctx.res, {
      afterRefresh: async (_req, _res, session) => {
        session.test = 'Hello World';
        return session;
      },
    });
    return { props: {} };
  },
});
```

And when I check my session looks like the session is not updated. Is it a bug or expected behavior?

If it's not a bug how I must update my session with `afterRefresh` method? And I didn't find any example for this case


### Reproduction

```
 export const getServerSideProps = withPageAuthRequired({
  returnTo: '/',
  async getServerSideProps(ctx) {
    await getAccessToken(ctx.req, ctx.res, {
      afterRefresh: async (_req, _res, session) => {
        session.test = 'Hello World';
        return session;
      },
    });
    return { props: {} };
  },
});
```

### SDK version

1.9.0

### Next.js version

10.2.3

### Node.js version

v16.13.0
