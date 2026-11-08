Enable attribute is ignored for tags
### Behaviour

Global attribute `enable` for `tags` input (see [docs](https://github.com/crazy-max/ghaction-docker-meta#tags-input)) is ignored - even though it's set to `"false"`, annotated tag is still created.

#### Steps to reproduce this issue

1. Include `enable=false` in `tags` input, e.g.:
```
tags: |
  type=raw,value=foo
  type=raw,value=bar,enable=false
```
2. Try to build/tag image.

#### Expected behaviour

List of docker tags should not include `bar`.

#### Actual behaviour

List of docker tags contains both `foo` and `bar`:

### Logs

```
Run crazy-max/ghaction-docker-meta@v2
  with:
    images: testimage
    tags: type=raw,value=foo,
  type=raw,value=bar,enable=false
    github-token: ***

Context info
  eventName: pull_request
  sha: 99b0a688a109ec11aaafe1c3bf4c07296274ff32
  ref: refs/pull/1/merge
  workflow: CI
  action: crazy-maxghaction-docker-meta
  actor: jakub-bacic
  runNumber: 25
  runId: 700974690

Docker image version
  foo

Docker tags
  testimage:foo
  testimage:bar
...
```

### Additional contract requirements

Any tag configured through the `tags` input with `enable=false` must be omitted from the generated Docker tags, regardless of its tag type.
