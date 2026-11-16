Request - sort by locale
Hey there,

Really cool program, it would be even better if we could use it manage non English files, such as those with CJK file names.

Right now `lf` does not respect the `LC_*` env variables, so for some languages it becomes very painful to browser larger directories.

Thanks :)

### Additional contract requirements

- Add a `locale` option (config key) that controls locale-aware ordering of the file list. The empty string disables locale ordering. The special value `*` selects the locale from the environment (`LC_*`/`LANG`). Any other value is an IETF BCP 47 language tag, and the file list is ordered according to that language's collation rules.
- Add a function `makeCollator(localeStr string, opts ...collate.Option) (*collate.Collator, error)` in `misc.go`, where `collate` is the package `golang.org/x/text/collate`. It returns a collator configured for the resolved language tag and the supplied options. It returns a non-nil error when `localeStr` is the empty string (locale ordering disabled) or when `localeStr` is not a valid language tag. When `localeStr` is `*`, the language tag is read from the environment.
