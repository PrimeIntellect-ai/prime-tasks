feat: comment directive "sort"
Often there's a series of ast siblings that codebase authors want to keep sorted. We know this to be the case for things like aliases, imports, etc, but what about arbitrary lists within the code? The author just has to put a comment like "please keep this sorted :(" and hope their coworkers play along.

But the whole point of styler is saving you from having to think about your coworkers preferences! (this is a joke. sort of.)

So maybe it could maintain this for us?

## Example Input

```elixir
# given
@my_list [
  # styler:sort
  :a,
  :quick,
  :brown,
  :fox
]
# get
@my_list [
  # styler:sort
  :a,
  :brown,
  :fox,
  :quick
]
```

could be neat!

### Additional contract requirements

- When sorting the commented dependency list, keep `# ecto` immediately before `{:ecto, "~> 3.12"}`, both `# genstage comment 1` and `# genstage comment 2` immediately before `{:gen_stage, "~> 1.0", override: true}`, `# hackney comment` immediately before `{:hackney, "1.18.1", override: true}`, and `# telemetry` immediately before `{:telemetry, "~> 1.0", override: true}`. Keep `# dangling comment` after the final entry.
