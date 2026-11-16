Logout is clearing credentials stored in local storage for ALL client_ids
### Describe the problem

We use [auth0-angular](https://github.com/auth0/auth0-angular) SDK to provide authentication for multiple Auth0 clients on the same website, with the `cacheLocation: 'localstorage'` configuration option.

In other words, the website https://example-website/A has its own login button for a Auth0 with `client_id_a`, and https://example-website/B has its own login button for a Auth0 configured with  `client_id_b`.

Because A and B share a hostname, they share the same local storage.

Login works as expected: when I login for A, I am not logged in for B, and reciprocally. This is because local storage keys  include the client_id, allowing to differentiate A and B.

But when I log out from A, the stored credentials for B are also cleared from the local storage, which should not happen.

### What was the expected behavior?

Logging out from sectionA should only clear out stored credentials for sectionA, without impacting stored credentials for sectionB.

### Reproduction

- On Auth0, configure two separate clients with each it's own client_id.

- Create an SPA that has a login/logout button, and configure it to use one or the other client_id based on the url /A or /B (or whatever), with option `cacheLocation: 'localstorage'`.

- Go to your-app/A, login for A

- Reload the page to your-app/B, login for B

- Check that local storage contains stored credentials for A and B.

- Reload the page to your-app/A, log**out** for A

- See that local storage was cleared of credentials for both A and B

### Environment

- **Version of `auth0-spa-js` used:** 1.22.5
- **Which browsers have you tested in?** Firefox, Chrome
- **Which framework are you using, if applicable (Angular, React, etc):** Angular
- **Other modules/plugins/libraries that might be involved:** [auth0-angular](https://github.com/auth0/auth0-angular)

### Possible cause

[HIDDEN]
