User Agent, or, Plans for LD_SINGLEFILE_OPTIONS
I see you stubbed out this config variable `LD_SINGLEFILE_OPTIONS` but aren't using it. One use case I have for it is passing user agent:

Does not work:
`single-file "https://reddit.com/" r.html`

Yields (truncated output):
```
<body>
 <h1>whoa there, pardner!</h1>
<p>Your request has been blocked due to a network policy.</p>
<p>Additionally make sure your User-Agent is not empty and is something unique and descriptive and try again.</p>
```

Works:
`single-file "https://reddit.com/" --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:124.0) Gecko/20100101 Firefox/124.0" r2.html`

Before I start work on it for a pull request, do you have any design requirements? Any specific arguments you want promoted to their own environment variable?

Ref https://github.com/sissbruecker/linkding/blob/edd958fff61a640cf02c7640b717e78f10322b8b/bookmarks/services/singlefile.py#L20-L23

### Additional contract requirements

- The `LD_SINGLEFILE_OPTIONS` setting holds additional command-line arguments for the `single-file` executable. Its value is split into individual arguments the way a shell would (for example, `--user-agent "some value"` yields the two arguments `--user-agent` and `some value`), and the resulting arguments are inserted between the `single-file` executable path and the URL/output-path arguments.
- When `LD_SINGLEFILE_OPTIONS` is empty, no additional arguments are inserted.
