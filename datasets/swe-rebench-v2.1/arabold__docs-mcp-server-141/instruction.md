Private Docs: Header Support for Authentication
Allowing arbitrary headers to be set for a source would enable internal documentation requiring authentication to be consumed.  For example, Confluence or something that needs an API token.

Allowing any header to be set would be most flexible, perhaps a JSON map of strings as an env variable would be the most flexible.

```json
{"Authorization": "Bearer ...."}
```

### Additional contract requirements

- Source-level scrape configuration exposes a `headers` option as a map of string header names to string values. Configured headers are included in HTTP requests made while scraping that source.
