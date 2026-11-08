Feat: add support for bootstrapping
Improve resilience by implementing the Bootstrap feature of Unleash. Feature write-up:
https://www.getunleash.io/blog/bootstrap-unleash-java-sdk-to-improve-the-resilience

Reference implementation:
* Java SDK: https://github.com/Unleash/unleash-client-java/pull/131
* Node SDK: https://github.com/Unleash/unleash-client-node/pull/283/files


We need to bootstrap to be adapted to what makes sense in Pyhton. It should at least allow:
- manual passing of "json string of the full feature toggle configuration",
- loading from file
- loading from URL.

If the user want to bootstrap from a URL we should probably try he actual Unleash API, and load the bootstrap URL as a fallback mechanism of the SDK fails to load it from the Unleash API. It will only load from bootstrap on the initial fetch.

### Additional contract requirements

- The bootstrap entry points are public methods on `UnleashClient.cache.FileCache`:
  - `bootstrap_from_dict(self, initial_config: dict) -> None`
  - `bootstrap_from_file(self, initial_config_file: pathlib.Path) -> None`
  - `bootstrap_from_url(self, initial_config_url: str) -> None`
- A bootstrapped `FileCache` can be passed to `UnleashClient` through its `cache` parameter, and the pre-seeded configuration is available for feature checks before the client is initialized.
- When the client initializes, it first tries to fetch configuration from the normal Unleash API. If that fetch succeeds, the API configuration is used; if the initial API fetch fails, the supplied bootstrap configuration remains available as the fallback. Bootstrap configuration is not fetched again as a source on subsequent refreshes.
