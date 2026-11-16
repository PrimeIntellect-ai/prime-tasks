Handle/Warn on unsupported flags
[HIDDEN]

```elixir
    [HIDDEN]
      command
      |> OptionParser.split()
      |> OptionParser.parse(
...
```
to generate some warnings, which flags have not been recognised and generate a better error message than

```elixir
** (MatchError) no match of right hand side value: []
    (curl_req 0.98.6) lib/curl_req/macro.ex:48: CurlReq.Macro.parse/1
    (curl_req 0.98.6) expanding macro: CurlReq.sigil_CURL/2
    iex:5: (file)
```

### Additional contract requirements

- Unsupported flags must produce a useful diagnostic rather than the uninformative MatchError.
- When `CurlReq.Macro.parse/1` encounters the unsupported flag `--foo`, it must raise `ArgumentError` with a message containing `Unknown "--foo"`.
