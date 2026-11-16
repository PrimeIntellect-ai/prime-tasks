`where` doesn't seem to work properly on atomics
**Describe the bug**
It appears that `where` is not working in conjunction a custom atomic validator. In this particular situation I am checking on the value of an aggregate like so:

```elixir
defmodule Is100Percent do
  use Ash.Resource.Validation

  def atomic(_changeset, _opts, context) do
    {
      :atomic,
      [:total_percentage],
      expr(^atomic_ref(:total_percentage) != 100),
      expr(
        error(^Ash.Error.Changes.InvalidAttribute, %{
          field: :total_percentage,
          message: ^(context.message || "must equal 100%"),
          value: ^atomic_ref(:total_percentage)
        })
      )
    }
  end
end
```

And here's the aggregate (close enough anyway, I'm being a bit cagy with names):

```elixir
aggregates do
  sum :total_percentage, :items, :percentage do
    default Decimal.new(0)
    public? true
  end
end
```

The validation works fine like this:

```elixir
update :update do
  primary? true
  accept [:status]

  validate Is100Percent
end
```

However, not like this:

```elixir
update :update do
  primary? true
  accept [:status]

  validate Is100Percent do
    where attribute_equals(:status, "active")
  end
end
```

The idea is I only want to validate this when that status matches.

Here's hopefully helpful SQL:

```elixir
Ash.update(resource, %{status: "active"}, authorize?: false)
```

This _should_ return an error but instead, the status is updated.

```sql
UPDATE "resources" AS a0 SET "id" = s1."__new_id", "status" = s1."__new_status" FROM (SELECT $1::varchar::varchar AS "__new_status", (CASE WHEN ($2::varchar::varchar != $3::varchar) AND (coalesce(ss1."total_percentage", $4::decimal)::decimal != $5::decimal) THEN ash_raise_error(jsonb_build_object('exception', $6::text, 'input', jsonb_build_object($7::text, $8::jsonb, $9::text, coalesce(ss1."total_percentage", $10::decimal)::decimal, $11::text, $12::jsonb))::jsonb, NULL::uuid) ELSE sa0."id"::uuid END)::uuid AS "__new_id", sa0."id" AS "id" FROM "resources" AS sa0 LEFT OUTER JOIN LATERAL (SELECT ssa0."resource_id" AS "resource_id", coalesce(sum(ssa0."percentage"::decimal), $13::decimal)::decimal AS "total_percentage" FROM "public"."itms" AS ssa0 WHERE (sa0."id" = ssa0."resource_id") GROUP BY ssa0."resource_id") AS ss1 ON TRUE WHERE (sa0."id"::uuid = $14::uuid)) AS s1 WHERE (a0."id" = s1."id") RETURNING a0."id", a0."created_at", a0."status" ["active", "active", "active", Decimal.new("0"), Decimal.new("100"), "Ash.Error.Changes.InvalidAttribute", "message", "must equal 100%", "value", Decimal.new("0"), "field", "total_percentage", Decimal.new("0"), "01936690-1a73-7f84-9eca-b7292d788a42"]
```

If I remove `when`, it works:

```sql
UPDATE "resources" AS a0 SET "id" = s1."__new_id", "status" = s1."__new_status" FROM (SELECT $1::varchar::varchar AS "__new_status", (CASE WHEN coalesce(ss1."total_percentage", $2::decimal)::decimal != $3::decimal THEN ash_raise_error(jsonb_build_object('exception', $4::text, 'input', jsonb_build_object($5::text, $6::jsonb, $7::text, coalesce(ss1."total_percentage", $8::decimal)::decimal, $9::text, $10::jsonb))::jsonb, NULL::uuid) ELSE sa0."id"::uuid END)::uuid AS "__new_id", sa0."id" AS "id" FROM "resources" AS sa0 LEFT OUTER JOIN LATERAL (SELECT ssa0."resource_id" AS "resource_id", coalesce(sum(ssa0."percentage"::decimal), $11::decimal)::decimal AS "total_percentage" FROM "public"."itms" AS ssa0 WHERE (sa0."id" = ssa0."resource_id") GROUP BY ssa0."resource_id") AS ss1 ON TRUE WHERE (sa0."id"::uuid = $12::uuid)) AS s1 WHERE (a0."id" = s1."id") RETURNING a0."id", a0."created_at", a0."status" ["active", Decimal.new("0"), Decimal.new("100"), "Ash.Error.Changes.InvalidAttribute", "message", "must equal 100%", "value", Decimal.new("0"), "field", "total_percentage", Decimal.new("0"), "01936694-4b0d-74cc-93f0-b7edbf883b3e"]
```

It looks like `where` is having the opposite effect?

```sql
($2::varchar::varchar != $3::varchar)
```

Or:

```
('active' != 'active')
```

It seems to me like the `where` clauses aren't being negated as expected.

For instance,`where present(:status)` yields `("status"::varchar::varchar IS NULL) AND`

Sure enough, if I do this:

```elixir
update :update do
  primary? true
  accept [:status]

  validate Is100Percent do
    where attribute_does_not_equal(:status, "active")
  end
end
```

Things trigger where they should (or shouldn't, lol). I get: `($2::varchar::varchar = $3::varchar) AND`

**To Reproduce**
It looks like where is just all backwards. If this hasn't been captured by normal testing, something in my specific validation is causing confusion. My guess would be it's related to the aggregate?

**Expected behavior**
The opposite of what is happening.

**Runtime**
- Elixir version 1.17.2
- Erlang version 27.0.1
- OS macOS 15.0.1
- Ash version 3.4.43

**Additional context**
[We discussed this in the Discord.](https://discord.com/channels/711271361523351632/711271361523351636/1310775099275874408)
