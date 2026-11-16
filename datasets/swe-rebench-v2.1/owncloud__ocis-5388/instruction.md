Return surname and givenName in identity.LDAP
The LDAP properties surname and givenName have recently become supported in user creation, but the properties aren't being populate by [HIDDEN] or [HIDDEN], and so the properties are invisible in the returns in the graph API.

Add these properties.

### Additional contract requirements

LDAP-backed user objects returned by the graph API must expose `surname` and `givenName` values sourced from their corresponding LDAP attributes. This applies to both single-user and user-list results.
