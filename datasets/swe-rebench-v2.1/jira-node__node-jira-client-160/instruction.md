Add override for api version
Hey mang,

we have a jira server we're using, would be nice if I could provide a function or something to override the pathname generated in makeUri because we have
example.com/rest/____
and get 404's when /api/${apiVersion} is in there.

### Additional contract requirements

`makeUri` accepts an optional per-call `intermediatePath` string alongside `pathname`. When supplied, it replaces the default REST API prefix for that URL; the supplied path is joined with the pathname to form the URL.
