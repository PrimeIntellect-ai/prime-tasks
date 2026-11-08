Disable suggestions in errors message
## Context
We have some mutation defined:
```graphql
  extend type Mutation {
    updateUserDetail(input: UpdateUserDetailsInput!): UpdateUserDetailsPayload
  }
```
The user sends the following query:
```graphql
mutation {
  updateUserDetil {
    user {
        id
    }
  }
}
```
The server will response with an error maintaining in the message: `"message": "Cannot query field \"updateUserDetil\" on type \"Mutation\". Did you mean \"updateUserDetail\"?",`

## The problem
In case of a private API, we generally want to avoid leaking information about our API. Disabling the introspection is a good step, but the recommendations are leaking some information that can be used by attackers. This [talk](https://youtu.be/NPDp7GHmMa0?t=1906) discuss this issue (from the perspective of a pentester).

## Propositions
1. Remove suggestions for any environment that is not development
2. Add a setting to force override the previous change

### Additional contract requirements

- `ApolloServer` accepts an optional boolean option named `hideSchemaDetailsFromClientErrors`, which defaults to `false`. When it is `true`, "Did you mean ...?" suggestions are removed from GraphQL validation error messages; when it is `false` or omitted, the suggestions remain in the messages in every environment. Changing the runtime environment alone does not change this default.
- The module `@apollo/server/plugin/disableSuggestions` exports a public function `ApolloServerPluginDisableSuggestions()`. Adding the plugin it returns to a server's `plugins` list removes "Did you mean ...?" suggestions from GraphQL validation error messages.
