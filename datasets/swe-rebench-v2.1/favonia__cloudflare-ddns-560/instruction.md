Add a custom provider
For my use case being able to configure a custom provider would be useful. It would basically be a http provider like ipify, but with the ability to use an env variable to configure any url.

### Additional contract requirements

- Add a public function `NewCustom(url string) Provider` in the package `internal/provider` (import path `github.com/favonia/cloudflare-ddns/internal/provider`). It creates a provider named `custom` that fetches the given URL over the HTTP(S) protocol and reports the retrieved IP address as the detected IP address.
- The custom provider can be selected in the configuration with the `url:` prefix, for example `IP4_PROVIDER=url:https://example.com` or `IP6_PROVIDER=url:https://example.com`. The text following `url:` is the URL to fetch.
