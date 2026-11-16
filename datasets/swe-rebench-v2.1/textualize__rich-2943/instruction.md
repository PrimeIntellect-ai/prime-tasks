[BUG] Style.clear_meta_and_links should reset hash
The hash of a `Style` instance depends on `_meta` and `_link`:

https://github.com/Textualize/rich/blob/6d30ad0f30028210124c149811cbbe2b183711f9/rich/style.py#L432-L445

So, when the link and meta are cleared with the method `Style.clear_meta_and_links`, the cached hash should be cleared:

https://github.com/Textualize/rich/blob/6d30ad0f30028210124c149811cbbe2b183711f9/rich/style.py#L664-L668
