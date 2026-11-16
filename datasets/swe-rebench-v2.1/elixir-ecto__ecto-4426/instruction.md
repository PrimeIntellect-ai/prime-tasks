Ecto.Changeset.merge do not merge types and do not raises when types are different
### Elixir version

1.16.1

### Database and Version

PostgreSQL: postgres:13-alpine

### Ecto Versions

3.11.2

### Database Adapter and Versions (postgrex, myxql, etc)

postgrex 0.17.4

### Current behavior

During the `Ecto.Changeset.merge/2` operation the type field of the changeset is not merged. Which result in a strange result when applying changes using schemaless changesets

```elixir
data = %{}
changeset1 = Ecto.Changeset.cast({data, %{field1: :string}}, %{field1: "field 1"}, [:field1])
changeset2 = Ecto.Changeset.cast({data, %{field2: :string}}, %{field2: "field 2"}, [:field2])
Ecto.Changeset.merge(changeset1, changeset2) |> Map.get(:types)
# %{field2: :string}

Ecto.Changeset.merge(changeset1, changeset2) |> Ecto.Changeset.apply_changes()
# %{field2: "field 2"}
```

Is it the expected behaviour?
[HIDDEN]

### Expected behavior

I can see 2 types of behaviour that could be acceptable:

1. Merge the types for easiness to use merge with schema less changeset
2. Raise if the types are not equals (like when the data from the changesets are different)

### Additional contract requirements

When `Ecto.Changeset.merge/2` combines schemaless changesets whose type maps contain different fields, the resulting changeset must retain the type information for every field present in either input. It must not silently discard entries or raise solely because the maps differ.
