Honor "outputs" front matter field in content adapters


```go
func TestIssue13689(t *testing.T) {
	t.Parallel()

	files := `
-- hugo.toml --
disableKinds = ['home','rss','section','sitemap','taxonomy','term']
[outputs]
page = ['html','json']
-- layouts/page.html --
html: {{ .Title }}
-- layouts/page.json --
json: {{ .Title }}
-- content/p1.md --
---
title: p1
---
-- content/p2.md --
---
title: p2
outputs:
  - html
---
-- content/_content.gotmpl --
{{ $page := dict "path" "p3" "title" "p3" }}
{{ $.AddPage $page }}

{{ $page := dict "path" "p4" "title" "p4" "outputs" (slice "html") }}
{{ $.AddPage $page }}
`

	b := hugolib.Test(t, files)

	b.AssertFileExists("public/p1/index.html", true)
	b.AssertFileExists("public/p1/index.json", true)
	b.AssertFileExists("public/p2/index.html", true)
	b.AssertFileExists("public/p2/index.json", false)
	b.AssertFileExists("public/p3/index.html", true)
	b.AssertFileExists("public/p3/index.json", true)
	b.AssertFileExists("public/p4/index.html", true)
	b.AssertFileExists("public/p4/index.json", false) // currently returns true
}
```

Although the example above tests regular pages, I would expect the page kind to be irrelevant.
