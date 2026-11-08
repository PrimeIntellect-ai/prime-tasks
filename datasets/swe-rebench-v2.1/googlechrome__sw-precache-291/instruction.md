url hashes count as cache misses
Like the title says.  `example.com` works, but `example.com#chapter2` counts as a cache miss and the page fails to load.

Is this a bug, or the intended behavior.  If it's intended, can we add a configuration option to strip hashes?  It could be done inside the `stripIgnoredUrlParameters` function.

### Additional contract requirements

- URL fragments must be ignored when looking up precached resources: a URL with a fragment must resolve to the same cache entry as the otherwise identical URL without one. This behavior applies by default and must not require a configuration option.
