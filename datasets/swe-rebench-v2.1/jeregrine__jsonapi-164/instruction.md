Links Usage Unclear
I've read over the docs and have done my best to grok the code, but I'm a bit confused on how to specify links.

Suppose I want to include a link for a Book's many Pages, I might want something like this:

```json
{
  "data": {
    "id": 123,
    "title": "Curious George"
  },
  "relationships": {
    "pages": {
      "self": "/api/book/123/relationship/pages"
// snip
```

Setting up my `BookView` isn't quite clear to me. If I override `links/2` it doesn't seem to do anything. Overriding `relationships/0` as so doesn't seem to work:

```elixir
def relationships do
  [pages: PageView]
end
```

I think I may be missing something obvious, but I could use a hand.

### Additional contract requirements

- `JSONAPI.Serializer.serialize(view_module, data, conn)` returns a map representing the JSON:API document for the resource. Unless the `:remove_links` option is set to `true`, the returned map contains a `:links` member whose value includes at least a `self` link equal to `view_module.url_for(data, conn)`.
- The view module's `links/2` callback is invoked with the resource data and the connection and returns a map of user-defined links. Unless the `:remove_links` option is set to `true`, every entry it returns is merged into the document's top-level `:links` member alongside the `self` link. Link names may be atoms or strings; each value is either a URL string or a nested link object of the form `%{href: url, meta: meta_map}`.
- When the `:remove_links` option is set to `true` (for example via `Application.put_env(:jsonapi, :remove_links, true)`), the serialized document omits its `:links` members, including the `self` link and any user-defined links.
