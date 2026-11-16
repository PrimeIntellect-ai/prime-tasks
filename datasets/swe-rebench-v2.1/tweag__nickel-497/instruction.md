Allow dashes in identifiers
**Is your feature request related to a problem? Please describe.**
 Dashes are common in option names. Currently one has to escape record fields with dashes inside because it is interpreted as a minus:

```nickel
{
  "foo-bar"."bar-baz" = null,
}
```

**Describe the solution you'd like**
As decided during the [standardization meeting](https://github.com/tweag/nickel/blob/master/notes/standardization-meeting-07.12.21.md), alow the dash character "-" as part of an identifier, as in Nix.

```nickel
{
  foo-bar.bar-baz = null,
}
```

This means that `a-b` is not parsed as subtraction anymore. Subtraction now requires spaces. But we expect this to be a minor inconvenience (or even good practice) in a configuration language, versus the field escaping annoyance.
