Add new error when using `/keys` without having set a master-key before (`missing_master_key`)
Following
- this product discussion: https://github.com/meilisearch/product/discussions/552
- this specification: https://github.com/meilisearch/specifications/pull/179

We want to create a new type of issue informing the users they are trying to reach a route (i.e `/keys`) that requires a master-key to be set when launching Meilisearch.

The new error
- return the HTTP code `401`
- has the `missing_master_key` error `code`
- has the `type`: `auth`
- is a synchronous error: it happens immediately when the users are trying to reach the route without having set a master-key before
- has the following format (`message` and `link` should as following):
- only concerns the `/keys` endpoint

```
{
    "message": "Meilisearch is running without a master key. To access this API endpoint, you must have set a master key at launch.",
    "code": "missing_master_key",
    "type": "auth",
    "link": "https://docs.meilisearch.com/errors#missing_master_key"
}
```

## TODO
- [ ] Implement the changes and merge to the `main` branch -> opened to external contribution. Tests need to be added 🔥
- [X] Update the related spec

## Impacted teams

@meilisearch/docs-team and maybe @meilisearch/integration-team.

----

Feel free to ask any questions to implement this issue. The core team is available to guide you through this contribution, even if it's your first one.
We recommend referring to the [CONTRIBUTING.md guidelines](https://github.com/meilisearch/meilisearch/blob/main/CONTRIBUTING.md), especially if it's your first contribution to this repository.
Thanks in advance for your involvement ❤️
