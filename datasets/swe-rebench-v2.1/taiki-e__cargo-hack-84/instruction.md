Warn when an excluded feature is included in a feature group
I just (accidentally) passed `--group-features foo,bar --exclude-features bar,baz`. This caused CI to fail as the feature was included (due to the `--group-features` flag). It would be nice to have some sort of warning emitted when an overlap is detected.

### Additional contract requirements

- When feature `a` is specified by both `--exclude-features` and `--group-features`, the warning must contain the exact substring "feature `a` specified by both --exclude-features and --group-features".
- - When feature `a` is specified by both `--exclude-features` and `--features`, the warning must contain the exact substring "feature `a` specified by both --exclude-features and --features".
- When feature `member1` is specified by both `--exclude-features` and `--optional-deps`, the warning must contain the exact substring "feature `member1` specified by both --exclude-features and --optional-deps".
- When feature `a` is specified by both `--exclude-features` and `--include-features`, the warning must contain the exact substring "feature `a` specified by both --exclude-features and --include-features".
- - For excluded feature `z` in package `real`, when that feature is not found, the warning must contain the exact substring "specified feature `z` not found in package `real`".
