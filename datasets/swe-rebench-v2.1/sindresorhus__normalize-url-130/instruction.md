Strip text fragment option
https://web.dev/text-fragments/. Text fragments are currently supported in Edge, Chrome, and some mobile browsers. Google use/used them in search results.

Expected behaviour:

- https://example.com/page#:~:text=hello -> https://example.com/page
- https://example.com/page#main:~:text=hello -> https://example.com/page#main
- https://example.com/page#main -> https://example.com/page#main

I currently need to do this but I'm not sure many will so maybe it's not worth having to maintain an option for it.

### Additional contract requirements

- `normalizeUrl` supports a `stripTextFragment` option. It defaults to `true`; setting it to `false` retains the text-fragment portion of the URL hash.
