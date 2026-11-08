Doesn't accept relative paths
`--args=~/foo/bar/1.json`

but

`--args=~/Users/me/foo/bar/1.json` works.

### Additional contract requirements

The CLI must accept a schema path beginning with `~/` and resolve it relative to the current user's home directory.
