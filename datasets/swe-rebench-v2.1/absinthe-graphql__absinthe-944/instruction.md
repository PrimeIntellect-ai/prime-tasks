[Enum] Default value not interpreted properly in case of keyword list
Given the following enum definition

```ex
enum :project_order_by do
  value :inserted_at_asc, as: [asc: :inserted_at]
  value :inserted_at_desc, as: [desc: :inserted_at]
end
```

and the following field with a default enum argument

```ex
field :projects, list_of(:project) do
  arg :order_by, non_null(:project_order_by), default_value: [asc: :inserted_at]
  resolve &Resolvers.Projects.list_projects/3
end
```

I get the following error

```
The default_value for an enum must be present in the enum values.

Could not use default value of `[asc: :inserted_at]` for :project_order_by.

Valid values are:

 * [desc: :inserted_at]
 * [asc: :inserted_at]
```

### Reason

https://github.com/absinthe-graphql/absinthe/blob/00601ffc3aac8f0ce989113330213ede70c66bbf/lib/absinthe/phase/schema/validation/default_enum_value_present.ex#L37-L38

[HIDDEN]

What is the reasoning behind using `List.wrap`?
*Edit: it was introduced in #762 to handle default value for `list_of(enum)`.*

### Environment

* Elixir version (elixir -v): Elixir 1.9.1 (compiled with Erlang/OTP 22)
* Absinthe version (mix deps | grep absinthe): 1.5.1

### Additional contract requirements

- For a scalar enum argument, accept a keyword-list default when the complete keyword-list value matches an enum value.
