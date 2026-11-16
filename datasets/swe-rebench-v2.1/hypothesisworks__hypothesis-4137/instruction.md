Filter-rewriting for comparisons on dates, times, and datetimes
(I strongly recommend reading https://github.com/HypothesisWorks/hypothesis/issues/3795 for context)

Pydantic has [a 'constrained `date`' type](https://docs.pydantic.dev/latest/api/types/#pydantic.types.condate), which uses `annotated-types` to express the comparison bounds.  We do _correctly_ support this by converting it to a filter, but it would be nice to then rewrite that filter to make the strategy efficient too - which I mentioned in https://github.com/pydantic/pydantic/issues/4682#issuecomment-2108858855.

And then while we're at it, it seems worth considering the same as applied to `time` and `datetime` classes (in the latter case, perhaps just for single-tz strategies, and/or filtering in addition to a bit of a rewrite) to ensure that the obvious extensions also work if and when someone implements those.
