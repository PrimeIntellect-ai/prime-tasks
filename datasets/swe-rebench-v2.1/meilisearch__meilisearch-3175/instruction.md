CLI stabilization: rename the dumps commands
Following this discussion: https://github.com/meilisearch/product/discussions/560
Specification: WIP

As part of the [CLI stabilization](https://github.com/meilisearch/meilisearch/issues/2752), we want to rename the dump commands.

- `dumps-dir` in the config file should be renamed to `dump-dir`
- `--dumps-dir` option when launching Meilisearch binary should be renamed `--dump-dir`
- `MEILI_DUMPS_DIR` env variable should be renamed to `MEILI_DUMP_DIR`

⚠️ Don't forget to change the [default config](https://github.com/meilisearch/meilisearch/blob/main/config.toml) file as well.

## Impacted teams

@meilisearch/integration-team, @meilisearch/cloud-team and @meilisearch/docs-team

## TODO

- [ ] Implement the changes and merge to the `main` branch
- [X] Update the related spec -> https://github.com/meilisearch/specifications/pull/204

### Additional contract requirements

- In the configuration file, the setting is spelled `dump_dir` (configuration file keys use snake_case, so the hyphenated `dump-dir` name corresponds to `dump_dir` in the file).
