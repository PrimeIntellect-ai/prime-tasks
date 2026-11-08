`no-synchronous-tests` rule not exposed
It seems that the new rule wasn't added to the [HIDDEN] file.

### Additional contract requirements

- Expose the `no-synchronous-tests` rule through the plugin’s public rules map so consumers can access it as `rules['no-synchronous-tests']`.
