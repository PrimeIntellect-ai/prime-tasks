Enable intersphinx cache by default?
We support caching intersphinx inventories, but this requires passing the `--enable-intersphinx-cache` option on the command line. I think it would make more sense to enable the cache by default and provide an option to disable it.

The default cache duration is only one day, so I don't think there is a big risk of working with stale data if we enable caching by default.
