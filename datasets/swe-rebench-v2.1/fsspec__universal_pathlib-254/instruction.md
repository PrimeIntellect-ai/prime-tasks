UPathStatResult doesn't allow for `st_birthtime` on Windows machines pre-3.12
The current implementation of `UPathStatResult` relies on a check of `os.stat_result` to determine which properties to expose, in particular `st_birthtime`. This means that any UPath object created within a Windows environment (through Python 3.11) will not have access to the `st_birthtime` property, regardless of whether the (possibly remote) filesystem provides that information.

One my main purposes for using universal pathlibs is to separate from the restrictions of a particular os implementation. I think it would make more sense for `st_birthtime` to always be available for UPath stat results, but to throw an error if the underlying filesystem didn't return that information.

A related issue is that `st_ctime` only returns the created time if the fsspec implementation assigned to the key `"ctime"`. It seems that most fsspec implementations use the key `"created"`. UPathStatResults are instantiated by `.from_info`, which sets all values to fall back on zero. Hence the `st_ctime` silently returns zero, while `st_birthtime` (the only property that uses the `"created"` key) doesn't exist.
