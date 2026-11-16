Read debug IDs from debugId field in sourcemaps
When uploading sourcemaps using `sentry-cli`, debug IDs should be read from the `"debugId"` field as well as the current `"debug_id"`.

The TC39 proposal is for `"debugId"` to become the actual name, see https://github.com/tc39/source-map/blob/8be0fe10ad042e13f4196d17b44ddedfd6a9df58/proposals/debug-id.md?plain=1#L100-L117. For now we can support it _in addition_ to `"debug_id"`.

This requires updates in `symbolic` and `rust-sourcemap`:

- [x] https://github.com/getsentry/symbolic/pull/874
- [x] https://github.com/getsentry/rust-sourcemap/pull/97

[HIDDEN]
- [ ] https://github.com/getsentry/sentry-cli/pull/2222
