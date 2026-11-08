Optional auto capitalization on changelog
## Description

The automatic changelog seems to automatically capitalize the first letter, like this:

`feat: add amazing feature`

> ### Feature
> * Add amazing feature (`abc1234`)

That can be useful, but it can also be misleading, for example:

`fix: do_stuff now does stuff`

> ### Fix
> * Do_stuff now does stuff (`xyz9876`)

I've had it happen a couple of times, where the first word of a commit message happens to be a case-sensitive name, and the changelog changes its capitalization.

## Use cases

It'd be useful in order to avoid case-sensitive names having their capitalization changed automatically.

> ### Feature
> * add amazing feature (`abc1234`)
> ### Fix
> * do_stuff now does stuff (`xyz9876`)

## Possible implementation

Having the auto capitalization enabled by default is okay I think, so I was thinking it could be an option in [the changelog section in the configuration](https://python-semantic-release.readthedocs.io/en/latest/configuration.html#changelog), something like `changelog_capitalize`, that could be set to false to disable the automatic capitalization.

### Additional contract requirements

Automatic capitalization remains enabled when the capitalization setting is omitted. When enabled, only the first letter of the description is capitalized; the remaining letters retain their original casing.
