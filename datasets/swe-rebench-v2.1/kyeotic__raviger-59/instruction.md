Base path matcher regexp is not case insensitive
Hi @kyeotic 👋

We had a bug ticket in production where our silly users decided to access our single page app by changing some part of the base path URL to be lowercase (silly I know).

Unfortunately that is something that we used to support before so we had to write a temporary fix on our side.

The issue is here: https://github.com/kyeotic/raviger/blob/ea4a3f5a345268bd56af9f0716b7e49bc936d32a/src/path.js#L78-L80

[HIDDEN]

Would it be possible to either make it case insensitive, or have an option to do so?

Thanks in advance!

### Additional contract requirements

- Base-path matching must be case-insensitive. This may be the default behavior, or it may be enabled through an option named `caseInsensitive` passed in the options object to `useRoutes`.
