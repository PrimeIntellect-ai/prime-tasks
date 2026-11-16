Defaults and filtering tweaks
Two tasks:
- [ ] Change min count default to 5 (better with strict mode as default)
- [ ] Add mode to consider ambiguous bases as missing in freq filtering

### Additional contract requirements

- The `build` command's minimum k-mer count option is `--min-count`, and its default value is 5.
- The `align` command accepts the flag `--filter-ambig-as-missing`, which enables treating ambiguous bases as missing during frequency filtering.
- Strict quality filtering is the default quality-filtering mode.
