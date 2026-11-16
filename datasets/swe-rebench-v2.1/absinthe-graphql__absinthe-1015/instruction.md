Import fields includes introspect fields
<!-- START BUG TEMPLATE (Please delete the rest of this if you're not filing a bug.) -->

If submitting a bug, please provide the following:

### Environment

* Elixir version (elixir -v): 1.10.2
* Absinthe version (mix deps | grep absinthe): 1.5.3
* Client Framework and version (Relay, Apollo, etc): none, tested on graphiql

### Expected behavior

```
type AnObjectInput {
  d: String!
}
```

### Actual behavior

```
type AnObjectInput {
  __typename: String
  d: String!
}
```

__typename is present in the type

### Relevant Schema/Middleware Code

```

  object :an_object do
    @desc """
    Meeting id.
    """
    field :id, non_null(:id)
    import_fields(:c)
  end

  input_object :an_object_input do
    import_fields(:c)
  end

  object :c do
    field :d, non_null(:string)
  end
```

### Additional contract requirements

- For input objects, `import_fields` must not import `__typename`.
