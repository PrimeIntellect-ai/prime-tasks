Failure to cascade page params from site config to pages created by content adapters
I noticed this on the docs site, where news items created from a content adapter no longer display a publication date.

The test below passes with v0.147.2 and earlier.

```go
func TestIssue13743(t *testing.T) {
	t.Parallel()

	files := `
-- hugo.toml --
disableKinds = ['home','rss','section','sitemap','taxonomy','term']
[cascade.params]
foo = 'bar'
[cascade.target]
path = '/p1'
-- content/_content.gotmpl --
{{ .AddPage (dict "title" "p1" "path" "p1") }}
-- layouts/all.html --
{{ .Title }}|{{ .Params.foo }}
`

	b := hugolib.Test(t, files)

	b.AssertFileContent("public/p1/index.html", "p1|bar") // actual content is "p1|"
}
```

The failure began in v0.147.3, presumably related to https://github.com/gohugoio/hugo/pull/13696.

### Additional contract requirements

A publication date configured through a site cascade must remain available for display on a matching page created by a content adapter.
