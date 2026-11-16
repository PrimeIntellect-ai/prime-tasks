New step: `output`
```
% curl -o foo.html https://elixir-lang.org/index.html
% curl --remote-name https://elixir-lang.org/index.html
```

Let's add:

```elixir
iex> Req.get!(url, output: path)
iex> Req.get!(url, output: :remote_name)
```

### Additional contract requirements

- After writing the file, the returned response body must be `""`.
- If `:remote_name` resolves to an empty filename, raise a `RuntimeError` with the message `cannot write to file ""`.
