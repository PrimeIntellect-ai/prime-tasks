Include tenant ID in saml login redirect
The shortened route must include the `tenantId`.

Currently it only contains the `token` & `uuid`:
`${store.baseUrl}auth/saml/idp/login?token=${data.token}&uuid=${store.user.userUuid}`

### Additional contract requirements

- The redirect query parameters must be ordered `tenant_id` first, then `token`, then `uuid`.
