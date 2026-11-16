download scene has stopped working
Appears the client is not passing authorization headers when following a redirect.

### Additional contract requirements

- When the client follows a cross-domain redirect, it must carry its API key in the
  destination URL as the `api_key` query parameter. Existing destination query
  parameters must be retained. The query parameter order and equivalent URL spellings
  (such as a trailing slash on the root path) are not significant.
