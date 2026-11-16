v0.25.0 RC : wrong error when getting a invalid dump UID
Using rc0 (I also tried on [this branch](https://github.com/meilisearch/MeiliSearch/pull/1989)), when trying to get a dump with a UID that does not exist, I get

```json
{
    "message": "Dump `20201001-110357260` not found.",
    "code": "dump_process_failed",
    "type": "internal",
    "link": "https://docs.meilisearch.com/errors#dump_process_failed"
}
```

I should get
```json
{
    "message": "Dump `20201001-110357260` not found.",
    "code": "dump_not_found",
    "type": "invalid_request",
    "link": "https://docs.meilisearch.com/errors#dump_not_found"
}
```

See: https://github.com/meilisearch/specifications/blob/develop/text/0061-error-format-and-definitions.md#dump_not_found

- [ ] fix bug
- [ ] 🔥 Add tests 🔥
