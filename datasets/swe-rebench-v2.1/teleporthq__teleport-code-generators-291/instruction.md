Project generators - duplicated files in the output
It was observed that the project generators have as output a `GeneratedFolder` structure that contains duplicated files in the following situation:
- the used UIDL contains a component named, for example, `my-component`
- the used template already contains a component named `my-component` (the same name as a component in the UIDL)

In this case, it is expected not to generate another file but to override the existing one.

[HIDDEN]

A nice to have feature regarding this would be to diff the files before and only apply the necessary updates. Maybe we can use the Github API for this.
