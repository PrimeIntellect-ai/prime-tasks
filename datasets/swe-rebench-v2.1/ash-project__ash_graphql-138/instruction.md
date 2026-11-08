Allow adding a description at the query/mutation level
**Is your feature request related to a problem? Please describe.**
Right now, the description shown in the Graphql docs is taken from the action description, but there could be multiple queries/mutation which actually use the same action (e.g. `:list` and `:get` could both use the default `:read` action).

**Describe the solution you'd like**
There should be a way to customize description at the query/mutation level.

**Describe alternatives you've considered**
It's possible to work around this by having multiple different actions with different descriptions which do the same thing, but this quickly spirals out of control if the actions need to be kept in sync.

**Express the feature either with a change to resource syntax, or with a change to the resource interface**

```elixir
queries do
  get :get_post, :read do
    description "Gets a single post by its ID"
  end

  list :list_posts, :read do
    description "Lists all posts"
  end
end
```

The description would basically be

[HIDDEN]

### Additional contract requirements

A query or mutation can provide its own description for GraphQL documentation. When no description is provided for that query or mutation, its GraphQL description is taken from the associated action.
