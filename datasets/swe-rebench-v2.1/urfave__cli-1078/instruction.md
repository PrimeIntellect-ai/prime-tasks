v2 feature: Add Destination for StringSliceFlag
## Checklist

* [x] Are you running the latest v2 release? The list of releases is [here](https://github.com/urfave/cli/releases).
* [x] Did you check the manual for your release? The v2 manual is [here](https://github.com/urfave/cli/blob/master/docs/v2/manual.md)
* [x] Did you perform a search about this feature? Here's the [Github guide](https://help.github.com/en/github/managing-your-work-on-github/using-search-to-filter-issues-and-pull-requests) about searching.

## What problem does this solve?

- My team want to start using the `Destination` values on flags so we can have our flag values strongly typed rather than stringly typed (i.e calling c.String("flag") etc.). I noticed that the `StringSliceFlag` does not have a `Destination` field like other flags do

## Solution description

- Solution would be to add a `Destination` field to `StringSliceFlag` that works the same as all other `Destination` flag fields do.
