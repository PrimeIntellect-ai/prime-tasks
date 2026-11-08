V0.25.0rc2 keys returned by GET /keys should be nested in a `results` field
**Describe the bug**
Return of the `GET /keys` route is for the moment returned as an array containing the keys.
Per the [specifications](https://github.com/meilisearch/specifications/blob/72d7eb508032f29aebde52451f785d52770fa6d4/text/0085-api-keys.md?plain=1#L360) it is described as being inside a `results` field

**To Reproduce**
Steps to reproduce the behavior:
1. make a requesting on `GET /keys`
2. Array with keys is returned

**Expected behavior**
Should be in a `results` field

**MeiliSearch version:** [e.g. v0.20.0]
v0.25.0rc2
