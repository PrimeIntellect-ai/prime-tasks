[Feature suggestion] Pass context to the callback function of Absinthe.Resolution.Helpers.dataloader/2 options
Hello everyone!

According to the docs, the callback function of Absinthe.Resolution.Helpers.dataloader options
> Can be used to e.g. compute fields on the return value of the loader.

This is a very useful way of transforming the data.

I think it this function would benefit from being passed the context, in case the data transformation needed to e.g. rely on session state.

Like this:
```
resolve dataloader(source, callback: fn (result, _parent, _args, context) ->
  {:ok, transform_data(result, context)}
end)
```

What do you think?

### Additional contract requirements

- `Absinthe.Resolution.Helpers.dataloader(source, opts)` and `Absinthe.Resolution.Helpers.dataloader(source, resource, opts)` both accept a `:callback` option.
- The `:callback` may be a function of arity 3, `(result, parent, args)`, or arity 4, `(result, parent, args, resolution)`, where `resolution` is the `Absinthe.Resolution` struct. It returns an `{:ok, value}` or `{:error, reason}` tuple.


- The arity-4 callbacks in the tested fields must receive a resolution whose `state` is `:unresolved`; the resulting organization names are `"Organization: #1 - unresolved"`, `"Organization: #2 - unresolved"`, and `"Organization: #3 - unresolved"`.
