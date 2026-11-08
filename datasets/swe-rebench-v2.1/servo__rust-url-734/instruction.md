`set_host` not working
In [the example](https://docs.rs/url/2.2.2/url/struct.Url.html#method.set_host), after calling `url.set_host(None)` the host is actually not set to `None`, but is `Some("")`.

[playground demo](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=cd9fddebf1aee0e6ffb947eb0ff7997e)

Not sure if this is related, but I also cannot seem to set host to `None` for certain types of URLs ([example](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=9e3735eaffb59424709d0a4947cede2b)). The error just says `EmptyHost` but I can't find any explanation of what this is supposed to mean.

### Additional contract requirements

Removing the host from a `file:` URL with an existing host, including `file://a/b/c`, must succeed and preserve its path. The result must serialize as a file URL with an empty authority host (for `file://a/b/c`, `file:///b/c`). Removing the host from the documented `foo://example.net` example must succeed and produce `foo:/`.
