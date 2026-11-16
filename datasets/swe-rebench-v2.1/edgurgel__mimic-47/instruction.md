Mimic.copy could be idempotent
When running `mix test--stale` from the top level of an umbrella app, and you have `Mimic.copy(M)` in two different app test_helper files, you'll get this error upon rerunning the tests with `--stale` (dunno why it doesnt happen without stale).

```
** (ArgumentError) Module M has already been copied.  See docs for Mimic.copy/1
    (mimic 1.7.2) lib/mimic.ex:506: Mimic.validate_server_response/2
    test/test_helper.exs:1: (file)
    (elixir 1.13.1) lib/code.ex:1183: Code.require_file/2
```

Unsure what the underlying issue is, but if Mimic ignored double `copy`s then we'd *maybe* be ok.
