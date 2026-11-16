CLI stabilization: change the behavior of `--schedule-snapshot`
Following this discussion: https://github.com/meilisearch/product/discussions/566
Specification: https://github.com/meilisearch/meilisearch/pull/3281

As part of the [CLI stabilization](https://github.com/meilisearch/meilisearch/issues/2752), we want to improve the snapshot command.

1. Remove `--snapshot-interval-sec`
2. `--schedule-snapshot` now accepts an interval in seconds
3. if `--schedule-snapshot` is given without any value, snapshots are activated with the default value (24h)

```bash
cargo run -- # gives no snapshot
cargo run -- --schedule-snapshot # gives snapshot every 24h
cargo run -- --schedule-snapshot 3600 # gives snapshot every hours
```

⚠️ Don't forget to change the [default config](https://github.com/meilisearch/meilisearch/blob/main/config.toml) file as well.

## Impacted teams

@meilisearch/docs-team

## TODO

- [ ] Implement the changes and merge to the `main` branch
- [ ] Update the related spec

### Additional contract requirements

- When `--schedule-snapshot` is not given, the running server does not schedule any snapshot tasks.
- `--schedule-snapshot` without a value schedules snapshot tasks every 86400 seconds (24 hours).
- `--schedule-snapshot N` with a numeric value `N` schedules snapshot tasks every `N` seconds.
- `--snapshot-interval-sec` is no longer accepted as a command-line option.
- The default `config.toml` no longer contains a `snapshot_interval_sec` key.
