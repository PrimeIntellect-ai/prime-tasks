(Potentially) tweak build tag return values for utils.parse_wheel_filename()
Right now, `packaging.utils.parse_wheel_filename()` returns `None` for a build tag if it isn't defined, `str` if it is. There are two potential ways of tweaking this.

(See https://github.com/pypa/packaging/pull/387 for background.)

# Return an empty string
One possible change is simply return the empty string instead of `None`. This just normalizes the return type.

# Return a tuple
Another option is to return a tuple. Pip uses `()` as a default and `(int, str)` if there is a build tag (as per [PEP 427](https://www.python.org/dev/peps/pep-0427/#file-name-convention)). The default could also be `(0, '')` to get similar sorting results as PEP 427 outlines. But the key point here is to automatically do the build tag parsing as appropriate to get people results.

## Perf consideration

Is it worth spending the (literal) energy on parsing build tags every time? For instance, if one was to parse every wheel file name in a large Simple repository index (e.g. https://download.pytorch.org/whl/torch_stable.html) and it happened to use build tags extensively, would it be worth parsing things ahead of time, or is it better to punt until absolutely necessary?

I think this comes down to whether build tags take precedence over wheel tags in wheel selection, or are they more of a tiebreaker when wheel tags are the same? E.g. is `pkg-2021.1-cp39-cp39-manylinux.whl` a better fit than `pkg-2021.1-42-py3-none-any.whl`, or the other way around if you want the best fit of a wheel? If wheel tags take precedence (typically), then doing the parsing work should only be done if necessary. But if a wheel tag (typically) takes precedence then pre-emptively doing it for a simpler API makes sense to me.

### Additional contract requirements

`parse_wheel_filename()` must represent the optional wheel build tag consistently: return `()` when no build tag is present, and return a two-item tuple `(number, suffix)` when one is present. The number is the leading decimal integer and the suffix is the remaining text, including an empty suffix when the tag contains only digits.
