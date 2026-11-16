Re-executing query doesn't work
Hi there. I'm trying to upgrade a project from `urql@1.11.6` to `urql@2.0.3`, and I'm running into an issue when trying to re-execute a query using the `'network-only'` request policy. I've created a minimal reproduction here https://github.com/bausmeier/urql-repro, and the request in question is [in the `AccountInfo` component](https://github.com/bausmeier/urql-repro/blob/b329302bc47af6dbecd1fc0222528b505785035c/src/AccountInfo.jsx#L20).

Effectively what I've got is two components which render alongside each other:
1. A panel which shows some details of the viewer's account.
2. A login form which on success [stores an access token](https://github.com/bausmeier/urql-repro/blob/b329302bc47af6dbecd1fc0222528b505785035c/src/LoginForm.jsx#L11) so that it can be added to the `Authorization` header of subsequent requests [in `fetchOptions`](https://github.com/bausmeier/urql-repro/blob/b329302bc47af6dbecd1fc0222528b505785035c/src/UrqlProvider.jsx#L9-L19).

The rough reproduction looks like this:

![2021-05-08-193100_grim](https://user-images.githubusercontent.com/116090/117548307-8fa9f400-b034-11eb-9c5e-5494a846ce4c.png)

The `viewer` query which I'm executing will return `null` if there is no `Authorization` header, and an object containing an id if there is an `Authorization` header.

What I expect to happen, and what _does_ happen with `urql@1.11.6`, is that when the "Refresh" button is pressed, a GraphQL network request is made to get the viewer. If an access token has been set by "logging in" then it should be included in the request, and the account info should display the viewer's id.

What actually happens with `urql@2.0.3` is that after the initial request is made on page load, pressing the "Refresh" button doesn't fire off any more GraphQL requests at all.

I may be doing something completely stupid, but this used to work with the older version of urql, and a similar approach works with Apollo, so I'm a bit perplexed as to why it's not working with the latest urql. I'm happy to provide more info if needed.
