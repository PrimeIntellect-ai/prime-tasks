pkg/connection: let's deprecate NewClient and NewClientWithSettings and add NewRegistryClient and NewRegistryClientWithSettings
https://github.com/apigee/registry/blob/7bc06ba752571bcb29b327c4351e0a810cc9e283/pkg/connection/client.go#L74

### Additional contract requirements

- In package `pkg/connection`, add a public function `NewRegistryClient(ctx context.Context) (RegistryClient, error)` that creates a Registry client using environment-derived settings.
- In package `pkg/connection`, add a public function `NewRegistryClientWithSettings(ctx context.Context, settings Settings) (RegistryClient, error)` that creates a Registry client from the supplied settings. Settings that do not specify an address are rejected with an error.
