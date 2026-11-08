Help find/change wallet config
Occasionally users will want to change an existing network config e.g. add or remove GRPC hosts.

importing again isn't ideal as the may wish to make one change rather than create new and remove old.

I don't mind if it is a command to update, a command to list networks including path to config or something else.

### Additional contract requirements

- Add a `network locate` command to the `vegawallet` CLI that reports the folder in which network configuration files are stored.
- When the command is run with `--output json`, it prints a JSON object containing a `path` field whose value is that folder.
- The reported folder is located under the home directory selected with the `--home` flag.
