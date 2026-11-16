The :transactional option should be renamed to :transactions
Super low hanging fruit that I've left around for (literally) years. The name `:transactional` doesn't really fit with the rest of the options, so `:transactions` is much better. It's a breaking change so I was waiting for the next major to have some substance before filing this.

### Additional contract requirements

- The rename is breaking: `:transactional` is no longer a supported option. Passing `:transactional` to `Cachex.Options.parse/2` must not enable transactions (the resulting cache's `:transactions` setting must remain `false`), whether the old key is ignored or rejected as invalid.
