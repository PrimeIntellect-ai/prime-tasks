Error "Binaries have to be case-exact by definition" when connecting Keycloak (SCIM-Client) to scimmy
When trying to define scimmy as an SCIM-Server in Keycloak, I'm getting the following error when loading the provider configuration.

`errorMessage: The attribute with the name 'urn:ietf:params:scim:schemas:core:2.0:User:x509Certificates.value' has an invalid declaration. Binaries have to be case-exact by definition.`

### Additional contract requirements

SCIM schema declarations for attributes of type `binary` must expose `caseExact` as `true`. This includes the `User.x509Certificates.value` declaration.
