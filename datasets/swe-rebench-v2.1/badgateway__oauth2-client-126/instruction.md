Revoke token
Hi there, looking at the client, I don't see a way to revoke a token. I believe (correct me if I'm wrong) that this is part of the OAuth spec, so it seems reasonable that the client ought to support it. For instance, the discovery server I'm working with returns a `revocation_endpoint`.

If there's already a way to do this with the client, I apologize. Please point me in the right direction. Otherwise, I would be happy to take a stab at a PR.

### Additional contract requirements

The client must expose token revocation through a public `revoke(token)` operation, accepting a token returned by a grant operation and submitting that token's access-token value to the server. When discovery metadata supplies a revocation endpoint, revocation must use that advertised endpoint.
