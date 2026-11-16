Should Filter Params Be Transformed?
Maybe I'm writing by tests wrong, but it seems like filter params aren't transformed. E.g. given...

```elixir
  plug JSONAPI.QueryParser,
    filter: ~w[dog-breed],
    view: MyApp.DogView
```

```
GET /api/foo?filter[dog-breed]="corgi"
```

Results in `%{"filter" => %{"dog-breed" => "corgi"}}`.

It seems to me that we should apply the underscore transformation a la attribute params. This would mean that we neither need to apply the transformation manually, nor does the client need KNOW how to write the params (e.g. if we're dasherized, we're always dasherized).

I know the filter portion of the spec is skimpy, but I figured I'd raise this. Thoughts?

### Additional contract requirements

- Add a public function `mime_type/0` in module `JSONAPI` that returns the JSON:API MIME type, `"application/vnd.api+json"`.
- Add a public plug module `JSONAPI.UnderscoreParameters` that provides `init/1` and `call/2`.
- `call/2` takes a `%Plug.Conn{}` and the plug options. When the request's `content-type` header is the JSON:API MIME type, it returns the connection with every key in its `params` map transformed from dasherized (`"foo-bar"`) to underscored (`"foo_bar"`), including keys of nested maps; values are left unchanged. When the `content-type` header is not the JSON:API MIME type, it returns the connection unchanged.
- `init/1` initializes the plug for use in a pipeline.
