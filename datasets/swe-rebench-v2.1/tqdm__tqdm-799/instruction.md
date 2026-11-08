specify bar width format-spec
- [x] I have visited the [source website], and in particular
  read the [known issues]
- [x] I have searched through the [issue tracker] for duplicates
- [x] I have mentioned version numbers, operating system and
  environment, where applicable:
  ```python
  import tqdm, sys
  print(tqdm.__version__, sys.version, sys.platform)
  ```

I can't find it, maybe I'm stupid, but I'd like to be able to set a width for the right side data (something like this)
```

Messages            : 100%|█| 99/99 [00:02<00:00, 36.14it/s]
Message             : 100%|█| 3/3 [00:00<00:00, 544.17it/s]
Channels            :  95%|█▏           | 36/38 [08:54<00:22, 11.18s/it]
Relations           : 100%|█| 99/99 [00:00<00:00, 157.06it/s]
```
It would be nice, to make it possible to align the end of the bar (channels is the awkward one here)

### Additional contract requirements

- Add a public class `Bar` in module `tqdm._tqdm`.
- `Bar.__init__(self, frac, default_len=10, charset=Bar.UTF)` accepts a
  progress fraction `frac` (between 0 and 1), a base bar width
  `default_len` (a positive integer, default 10), and a `charset` string
  (default `Bar.UTF`), and stores them.
- `Bar.__format__(self, format_spec)` returns the rendered bar so that
  `Bar` objects can be used in `str.format` calls. `format_spec` is an
  optional `[width][type]`:
  - `width` is an integer. A non-negative width sets a fixed bar width.
    A negative width is subtracted from the bar's default length. If
    omitted, the bar's default length is used.
  - `type` is a single character: `a` selects the ASCII charset, `u`
    selects the Unicode charset, and `b` selects a blank charset. If
    omitted, the bar's stored charset is used.
  - The rendered bar has exactly the computed width, drawn with the
    selected charset, with whitespace padding and a fractional symbol
    reflecting `frac`.
- The class exposes the charset constants `Bar.ASCII` and `Bar.UTF` (the
  default).
- `{bar}` in a `bar_format` string accepts the same `[width][type]`
  format specifier, so a fixed bar width can be requested to align the
  end of the bar in progress output.
