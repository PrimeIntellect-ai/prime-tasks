devpi use does not store basic auth anymore (devpi-client 6.x regression)
Hello!
I saw that Basic authentication was unfortunately deprecated, but it judging by the code it should still work, right?

Our problem is that `devpi use` does not seem to store Basic authentication credentials anymore. Moreover, it errors out with `401 Unauthorized` at the end although most of the steps seem to work.

Our workflow basically starts with
```
devpi use https://username:password@devpi.example.com/some/index
```

This works as expected with `devpi-client` 5.x.

However, `devpi-client` 6.x errors out on `hub.validate_index_access()` in `use.py`::`main(...)`. By the time this method is invoked, it seems that no credentials are stored. The first `http_api` call seems to use the auth correctly.

No credentials are stored in `~/.devpi/client/current.json` either. They are stored with `devpi-client` 6.x.
