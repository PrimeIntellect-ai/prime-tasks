Introspection query fails when using a prototype schema that defines types for use by directive arguments
If submitting a bug, please provide the following:

### Environment

* Elixir version (elixir -v): 1.14.4
* Absinthe version (mix deps | grep absinthe): 1.7.5
* Client Framework and version (Relay, Apollo, etc): N/A

### Expected behavior

When using a prototype schema that defines directives as well as types used for the directives' arguments, the introspection query should succeed and return directives used by the schema as well as the argument types.

### Actual behavior

The introspection query fails:
```elixir
iex(1)> Absinthe.Schema.introspect(MyAppWeb.Schema)
{:ok,
 %{
   data: %{"__schema" => nil},
   errors: [
     %{
       locations: [%{column: 3, line: 64}],
       message: "Cannot return null for non-nullable field",
       path: ["__schema", "directives", 2, "args", 0, "type"]
     }
   ]
 }}
```

Poking around the schema (not the prototype schema) using `Absinthe.Schema.lookup_*` functions reveals that the directives resolve properly but looking up the custom argument types returns `nil`:
<details>
  <summary>iex output</summary>

  ```elixir
  iex(1)> Absinthe.Schema.lookup_directive(MyAppWeb.Schema, "feature")
  %Absinthe.Type.Directive{
    name: "feature",
    description: nil,
    identifier: :feature,
    args: %{
      complex: %Absinthe.Type.Argument{
        identifier: :complex,
        name: "complex",
        description: nil,
        type: :complex,
        deprecation: nil,
        default_value: nil,
        definition: nil,
        __reference__: nil
      },
      name: %Absinthe.Type.Argument{
        identifier: :name,
        name: "name",
        description: nil,
        type: %Absinthe.Type.NonNull{of_type: :string},
        deprecation: nil,
        default_value: nil,
        definition: nil,
        __reference__: nil
      },
      number: %Absinthe.Type.Argument{
        identifier: :number,
        name: "number",
        description: nil,
        type: :integer,
        deprecation: nil,
        default_value: nil,
        definition: nil,
        __reference__: nil
      }
    },
    locations: [:argument_definition, :enum, :enum_value, :field_definition,
    :input_field_definition, :input_object, :interface, :object, :scalar,
    :schema, :union],
    expand: {:ref, MyAppWeb.SchemaPrototype,
    {Absinthe.Blueprint.Schema.DirectiveDefinition, :feature}},
    definition: MyAppWeb.SchemaPrototype,
    repeatable: true,
    __private__: [],
    __reference__: %{
      location: %{
        file: "/home/david/Documents/com5737-repro/repro/lib/my_app_web/schema_prototype.ex",
        line: 12
      },
      module: MyAppWeb.SchemaPrototype
    }
  }
  iex(2)> Absinthe.Schema.lookup_type(MyAppWeb.Schema, "Complex")
  nil
  iex(3)> Absinthe.Schema.lookup_type(MyAppWeb.SchemaPrototype, "Complex")
  %Absinthe.Type.InputObject{
    name: "Complex",
    description: nil,
    fields: %{
      str: %Absinthe.Type.Field{
        identifier: :str,
        name: "str",
        description: nil,
        type: :string,
        deprecation: nil,
        args: %{},
        config: nil,
        triggers: [],
        middleware: [],
        complexity: nil,
        default_value: nil,
        __private__: [],
        definition: MyAppWeb.SchemaPrototype,
        __reference__: %{
          location: %{
            file: "/home/david/Documents/com5737-repro/repro/lib/my_app_web/schema_prototype.ex",
            line: 5
          },
          module: MyAppWeb.SchemaPrototype
        }
      }
    },
    identifier: :complex,
    __private__: [__absinthe_referenced__: true],
    definition: MyAppWeb.SchemaPrototype,
    __reference__: %{
      location: %{
        file: "/home/david/Documents/com5737-repro/repro/lib/my_app_web/schema_prototype.ex",
        line: 4
      },
      module: MyAppWeb.SchemaPrototype
    }
  }
  ```
</details>

### Relevant Schema/Middleware Code
I really just copied the schemas from [`type_system_directive_test.exs`](https://github.com/absinthe-graphql/absinthe/blob/master/test/absinthe/schema/type_system_directive_test.exs).

#### Prototype schema
<details>
  <summary>Code</summary>

  ```elixir
  defmodule MyAppWeb.SchemaPrototype do
    use Absinthe.Schema.Prototype

    input_object :complex do
      field :str, :string
    end

    directive :external do
      on [:field_definition]
    end

    directive :feature do
      arg :name, non_null(:string)
      arg :number, :integer
      arg :complex, :complex

      repeatable true

      on [
        :schema,
        :scalar,
        :object,
        :field_definition,
        :argument_definition,
        :interface,
        :union,
        :enum,
        :enum_value,
        :input_object,
        :input_field_definition
      ]
    end
  end
  ```
</details>

#### Schema
<details>
  <summary>Code</summary>

  ```elixir
  defmodule MyAppWeb.Schema do
    use Absinthe.Schema

    @prototype_schema MyAppWeb.SchemaPrototype

    schema do
      directive :feature, name: ":schema"
      field :query, :query
    end

    query do
      field :post, :post do
        directive :feature, name: ":field_definition"
      end

      field :sweet, :sweet_scalar
      field :which, :category
      field :pet, :dog

      field :search, :search_result do
        arg :filter, :search_filter, directives: [{:feature, name: ":argument_definition"}]
        directive :feature, name: ":argument_definition"
      end
    end

    object :post do
      directive :feature, name: ":object", number: 3

      field :name, :string do
        deprecate "Bye"
      end
    end

    scalar :sweet_scalar do
      directive :feature, name: ":scalar"
      parse &Function.identity/1
      serialize &Function.identity/1
    end

    enum :category do
      directive :feature, name: ":enum"
      value :this
      value :that, directives: [feature: [name: ":enum_value"]]
      value :the_other, directives: [deprecated: [reason: "It's old"]]
    end

    interface :animal do
      directive :feature, name: ":interface"

      field :leg_count, non_null(:integer) do
        directive :feature,
          name: """
          Multiline here?
          Second line
          """
      end
    end

    object :dog do
      is_type_of fn _ -> true end
      interface :animal
      field :leg_count, non_null(:integer)
      field :name, non_null(:string), directives: [:external]
    end

    input_object :search_filter do
      directive :feature, name: ":input_object"

      field :query, :string, default_value: "default" do
        directive :feature, name: ":input_field_definition"
      end
    end

    union :search_result do
      directive :feature, name: ":union"
      types [:dog, :post]

      resolve_type fn %{type: type}, _ -> type end
    end
  end
  ```
</details>
