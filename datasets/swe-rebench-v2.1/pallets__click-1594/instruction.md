Duplicate Boolean flag options "--foo/--foo" are not detected (defaults to False)
I ran into an issue where I had the code:

    @click.option( "--print-verbose-info/--print-verbose-info", help="...", default=False )

...and running `cli.py --print-verbose-info` was apparently defaulting over to the `False` value.  Totally my mistake (it should have been `--no-print-verbose-info`), but it'd be nice to get a warning/error for boolean values which match exactly (ie: cannot be set to true).

It was kindof tricky to diagnose b/c I assumed that the `--print-verbose-info` that I was passing on the CLI was triggering the `True` path, not the `False` path, and usually Click option parsing is pretty bulletproof so it took a while to find that copy/paste problem.

This would be a `good-first-issue`, I'm submitting it now more as a reminder to maybe follow-up on it and figure out the appropriate P.R.

### Additional contract requirements

- When constructing a Boolean flag option with identical true and false names, such as `click.Option(["--foo/--foo"], default=False)`, raise `ValueError` with a message containing `cannot use the same flag for true/false`.
