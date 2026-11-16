download_all callback
**[Original report](https://bitbucket.org/geostorm/eodag/issue/121) by me.**

----------------------------------------

When using download_all, provide the availability to launch a callback when each individual download in finished

### Additional contract requirements

- `EODataAccessGateway.download_all` accepts an optional `downloaded_callback` argument that defaults to `None`. When a callback is provided, it is called once with the downloaded product after each individual product download finishes.
- `download_all` returns a list of the local file system paths of the products that were downloaded, and returns an empty list when the given search result is `None`.
- A public class `DownloadedCallback` is available in the `eodag.utils` module. It is callable with a single argument, the downloaded product (an `EOProduct`).
