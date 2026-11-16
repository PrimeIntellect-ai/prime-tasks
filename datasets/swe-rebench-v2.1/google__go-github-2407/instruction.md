Support updated GitHub Pages Update API
In former versions of the GitHub API the pages update request used a `source` field of type `string`, with the branch name and a path delimited by a space. According to the current [GitHub documentation](https://docs.github.com/en/rest/pages#update-information-about-a-github-pages-site) and experiments with `curl`, the update api apparently now also supports the `source` parameter to be a struct like `{Branch: string, Path: string}`.

Looking at the required changes I think that this might break existing consumers of go-github using the PagesUpdate request - correct me if I'm wrong. I'm not sure if you prefer to have some kind of migration path supporting both versions or if a breaking change would be tolerable (maybe communicated with a major version bump). If you have any preference, please leave a note or a code pointer with an example how you'd like me to handle this.

See https://github.com/integrations/terraform-provider-github/issues/1198 for the motivation, and #2371 where the same requirement came up already. The planned change would also make the _create_ and _update_ pages code more consistent.

I've already started on a patch and I'm going to submit the pull request in the next days, so we might have a discussion on the actual change.

---

To show the desired effect, here are some examples using `curl`:

```
curl -X PUT https://api.github.com/repos/gesellix/pages-test/pages \
  -H 'Accept: application/vnd.github.v3+json' \
  -H 'Content-Type: application/json' \
  -H 'User-Agent: go-github' \
  -d '{"source":"main /docs"}' \
  -w "\n%{http_code}\n"
{"message":"Invalid request.\n\nInvalid property /source: `main /docs` is not a possible value. Must be one of the following: gh-pages, master, master /docs.","documentation_url":"https://docs.github.com/rest/reference/repos#update-information-about-a-github-pages-site"}
422
```

```
curl -X PUT https://api.github.com/repos/gesellix/pages-test/pages \
  -H 'Accept: application/vnd.github.v3+json' \
  -H 'Content-Type: application/json' \
  -H 'User-Agent: go-github' \
  -d '{"source":{"branch":"main","path":"/docs"}}' \
  -w "\n%{http_code}\n"

204
```

```
curl -X PUT https://api.github.com/repos/gesellix/pages-test/pages \
  -H 'Accept: application/vnd.github.v3+json'\
  -H 'Content-Type: application/json'\
  -H 'User-Agent: go-github'\
  -d '{"source":{"branch":"master","path":"/docs"}}'\
  -w "\n%{http_code}\n"

204
```

```
curl -X PUT https://api.github.com/repos/gesellix/pages-test/pages \
  -H 'Accept: application/vnd.github.v3+json'\
  -H 'Content-Type: application/json'\
  -H 'User-Agent: go-github'\
  -d '{"source":{"branch":"gh-pages","path":"/docs"}}'\
  -w "\n%{http_code}\n"

204
```

```
curl -X PUT https://api.github.com/repos/gesellix/pages-test/pages \
  -H 'Accept: application/vnd.github.v3+json' \
  -H 'Content-Type: application/json'\
  -H 'User-Agent: go-github'\
  -d '{"source":{"branch":"gh-pages","path":"/wiki"}}'\
  -w "\n%{http_code}\n"
{"message":"Invalid request.\n\nInvalid property /source: `/wiki` is not a possible value. Must be one of the following: /, /docs.","documentation_url":"https://docs.github.com/rest/reference/repos#update-information-about-a-github-pages-site"}
422
```

```
curl -X PUT https://api.github.com/repos/gesellix/pages-test/pages \
  -H 'Accept: application/vnd.github.v3+json'\
  -H 'Content-Type: application/json'\
  -H 'User-Agent: go-github'\
  -d '{"source":{"branch":"gh-pages","path":"/"}}'\
  -w "\n%{http_code}\n"

204
```

### Additional contract requirements

- In Go, expose `PagesUpdate.Source` as `*PagesSource`, with `PagesSource.Branch` and `PagesSource.Path` each of type `*string`.
