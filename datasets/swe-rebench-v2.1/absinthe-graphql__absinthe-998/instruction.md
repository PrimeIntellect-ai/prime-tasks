Introspection query breaks in the presence of query filters with default value
### Environment

* Elixir version (elixir -v):
```bash
Erlang/OTP 22 [erts-10.5] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1]
Elixir 1.9.4 (compiled with Erlang/OTP 20)
```
* Absinthe version (mix deps | grep absinthe):
`1.5.1`
* Client Framework and version (Relay, Apollo, etc):
`/graphiql`

### Relevant Schema/Middleware Code

Suppose the following schema
```elixir
input_object :filters do
  field :is_even, :boolean
end

query do
  field :numbers, list_of(:integer) do
    arg :filters, :filters, default_value: %{}
    resolve fn _, _, _ -> {:ok, [1,2,3]} end
  end
end
```

### Expected behavior

* The introspection query sent by the client should not break (and when it breaks auto-completion is no longer available), since queries sent against this schema succeed without error.
* Or perhaps as a first step it could perhaps output better diagnostics on error to help debug.

### Actual behavior

Enabling debugger output we can see the introspection query sent by graphiql as
```
query IntrospectionQuery {
    __schema {
      queryType { name }
      mutationType { name }
      types {
        ...FullType
      }
      directives {
        name
        description
        locations
        args {
          ...InputValue
        }
      }
    }
  }

  fragment FullType on __Type {
    kind
    name
    description
    fields(includeDeprecated: true) {
      name
      description
      args {
        ...InputValue
      }
      type {
        ...TypeRef
      }
      isDeprecated
      deprecationReason
    }
    inputFields {
      ...InputValue
    }
    interfaces {
      ...TypeRef
    }
    enumValues(includeDeprecated: true) {
      name
      description
      isDeprecated
      deprecationReason
    }
    possibleTypes {
      ...TypeRef
    }
  }

  fragment InputValue on __InputValue {
    name
    description
    type { ...TypeRef }
    defaultValue
  }

  fragment TypeRef on __Type {
    kind
    name
    ofType {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                }
              }
            }
          }
        }
      }
    }
  }
```
and this breaks with the following error

```bash
iex(1)> [info] Sent 500 in 31ms
[error] #PID<0.756.0> running SbApiWeb.Endpoint (connection #PID<0.751.0>, stream id 3) terminated
Server: localhost:4000 (http)
Request: POST /graphiql
** (exit) an exception was raised:
    ** (Absinthe.SerializationError) Value nil is not a valid boolean

        (absinthe) lib/absinthe/type/built_ins/scalars.ex:91: Absinthe.Type.BuiltIns.Scalars.serialize_boolean/1
        (absinthe) lib/absinthe/type/built_ins/introspection.ex:357: Absinthe.Type.BuiltIns.Introspection.render_default_value/4
        (absinthe) lib/absinthe/type/built_ins/introspection.ex:347: Absinthe.Type.BuiltIns.Introspection.render_default_value/4
        (elixir) lib/enum.ex:1336: Enum."-map/2-lists^map/1-0-"/2
        (absinthe) lib/absinthe/type/built_ins/introspection.ex:331: Absinthe.Type.BuiltIns.Introspection.render_default_value/4
        (absinthe) lib/absinthe/type/built_ins/introspection.ex:293: anonymous fn/2 in Absinthe.Type.BuiltIns.Introspection.__absinthe_function__/2
        (absinthe) lib/absinthe/resolution.ex:206: Absinthe.Resolution.call/2
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:231: Absinthe.Phase.Document.Execution.Resolution.reduce_resolution/1
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:186: Absinthe.Phase.Document.Execution.Resolution.do_resolve_field/3
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:171: Absinthe.Phase.Document.Execution.Resolution.do_resolve_fields/6
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:88: Absinthe.Phase.Document.Execution.Resolution.walk_result/5
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:114: Absinthe.Phase.Document.Execution.Resolution.walk_results/6
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:103: Absinthe.Phase.Document.Execution.Resolution.walk_result/5
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:281: Absinthe.Phase.Document.Execution.Resolution.build_result/3
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:171: Absinthe.Phase.Document.Execution.Resolution.do_resolve_fields/6
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:88: Absinthe.Phase.Document.Execution.Resolution.walk_result/5
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:114: Absinthe.Phase.Document.Execution.Resolution.walk_        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:103: Absinthe.Phase.Document.Execution.Resolution.walk_result/5
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:281: Absinthe.Phase.Document.Execution.Resolution.build_result/3
        (absinthe) lib/absinthe/phase/document/execution/resolution.ex:171: Absinthe.Phase.Document.Execution.Resolution.do_resolve_fields/6
```

The problem is the `default_value: %{}` specified on the `:filters` field, if no default value is specified introspection has no problems, but then I need to make my resolution code more complex to account for the presence of `nil` in the argument.filters instead of being able to simply work against the presence of fields in the dictionary. Which is admittedly a small problem (thank god for pattern matching), I just thought it curious that it only breaks for introspection and not for regular queries and that's why I thought to report this.

Thank you for reading!

### Additional contract requirements

- Introspection must complete successfully when an input-object argument default omits fields, including when the default is an empty object.
- The rendered default must preserve every supplied field and value and must not add omitted fields. The order of fields in an input-object literal is not significant.
