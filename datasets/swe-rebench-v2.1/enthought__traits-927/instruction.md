HasTraits._notifiers method not showing up in dir()
The `HasTraits.__dir__` implementation appears to suppress names of some methods that would otherwise show up. An example is the `_notifiers` method. For introspection purposes, it would be very useful to have those method names appear as normal.
