importing an activation token must handle IssuerAccount
When importing a token, if the account issuer is set the import must set the src account to IssuerAccount.

### Additional contract requirements

When generating an activation token with a signing key (the signer is not the account's own key), the generated token's `IssuerAccount` field must be set to the subject of the account that owns the signing key (the account's subject), not to the account claim's issuer.
