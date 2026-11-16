Rename short `request` and `response` related variable names
As we had received some feedback from users which have no related background to varnish, which inspired us to use `bereq`, `beresp` and `req` as names, we would like to refine this configuration part to be more expressive instead of the requirement looking up variable name specifications in the first place.

Following renames:
`req` -> `request`
`ctx` -> `context`
`bereq` -> removed
`beresp` -> removed
`bereqs` -> `backend_requests`
`beresps` -> `backend_responses`

`bereq` and `beresp` were shortcuts for `beresps.default.var`. There is no drop in replacement at the moment and we will discuss a possible `default` label shortcut later on. Accessing the `default` one: `backend_responses.default.*`.
