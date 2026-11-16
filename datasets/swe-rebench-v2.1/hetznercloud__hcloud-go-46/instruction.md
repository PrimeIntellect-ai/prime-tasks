Implement updating a server
https://docs.hetzner.cloud/#resources-servers-put

### Additional contract requirements

- Expose the operation as `ServerClient.Update`, accepting a server and `ServerUpdateOpts`.
- `ServerUpdateOpts` has an optional `Name` string field. When supplied, the name is sent in the update request to update the server's name.
