[Feature request] Add custom additional headers in each requests
Hello,

I started using this provider recently and it works fine, amazing job!

Now the hard part: our production keycloak is hidden behind a proxy which filters requests not having a special custom header (key and value).

I'm currently working on implementing a new parameter for the setup of the provider itself to include this feature.
This will mirror what is already available in a python library we were using: https://github.com/marcospereirampj/python-keycloak/blob/ff4669979973c3744dfcfb415840b44dcaf88a5c/keycloak/keycloak_openid.py#L55

### Additional contract requirements

- Provider configuration exposes an optional `additional_headers` map of header names to values, and its entries are applied to requests made by the configured client.
- The `keycloak` package's `NewKeycloakClient` constructor must have the signature:

  `NewKeycloakClient(url string, basePath string, clientId string, clientSecret string, realm string, username string, password string, initialLogin bool, clientTimeout int, caCert string, tlsInsecureSkipVerify bool, userAgent string, additionalHeaders map[string]string) (*KeycloakClient, error)`

- Every entry of the supplied `additionalHeaders` map must be attached to each outgoing Keycloak REST request, including authentication/token requests and admin API requests.
