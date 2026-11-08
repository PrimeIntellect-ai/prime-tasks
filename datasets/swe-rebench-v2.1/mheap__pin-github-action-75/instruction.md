Private repos require you to set process.env.GH_ADMIN_TOKEN to fetch the latest SHA
Hellos @mheap. Thanks for this excellent tool.

I am running it against build files in a public repo and getting an unexpected error:
```
Unable to find SHA for actions/checkout@v2
Private repos require you to set process.env.GH_ADMIN_TOKEN to fetch the latest SHA
```

These are the specific actions triggering the issue:
```
Unable to find SHA for actions/checkout@v2
Unable to find SHA for actions/github-script@v3
Unable to find SHA for actions/github-script@v3.1.0
Unable to find SHA for dorny/paths-filter@v2
Unable to find SHA for hmarr/debug-action@v2
```

My understanding is that these are not private repos and shouldn't require a token. `uses: actions/checkout@main` is an example in your own home page.

I can work around the issue for now, but it does complicate my team's usage of the tool so it's worth asking about.

### Additional contract requirements

- When the GitHub API rejects a lookup because of rate limiting, the rejection message must be exactly:
```
Unable to find SHA for nexmo/github-actions@master
API rate limit exceeded for 1.2.3.4. (But here's the good news: Authenticated requests get a higher rate limit. Check out the documentation for more details.)
```
