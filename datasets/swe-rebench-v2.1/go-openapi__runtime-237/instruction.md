Authorization token
Hi all.

I have met with not clear logic or bug with setting auth token for generated client.

As for my code i set default token via:

```go
....
import (
    "github.com/go-openapi/runtime/client"

    "github.com/myproject/internal/generated/clients/myextservice/client/orders"
)
....
func NewClient(host, basePath, scheme, token string) {
....
    t := client.New(host, basePath, []string{scheme})
    t.DefaultAuthentication = client.BearerToken(token)
....
}
```

Than later in specific client method for external api endpoint i need to set a different token(business logic of external service) and do this via:
```go
func (c *Client) CreateOrder(ctx context.Context, token string) {
....
    params := orders.
        NewCreateOrderParamsWithContext(ctx).
        WithBody(body).
        WithAuthorization(token)

    resp, err := c.client.Orders.CreateOrder(params)
....
}
```
As for debug info request was sending with default token and no overwrite was made by passing params struct with new token(assigned by `WithAuthorization(token)`)  to `CreateOrder(params)` method


[HIDDEN]

Expected behavior:

- `WithAuthorization(token)` overwrites the default client token, assigned on it's creation
