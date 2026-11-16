delete or revoke users
add command to delete/revoke users

### Additional contract requirements

Expose deletion as `nsc delete user <name>`, with the user name supplied positionally. The command must accept the `--revoke` option to revoke a user's credentials as an optional action performed along with deleting that user. When revocation is requested, the user's public key must be recorded as revoked in the account claim.

Deleting a user without `--revoke` must remain possible and must not add that user's public key to the account's revocations.
