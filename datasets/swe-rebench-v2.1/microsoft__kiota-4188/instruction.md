Deprecation information generates templates without resolving the types in the templates.
[HIDDEN] The template is therefore generated withoour resolving the type parameters.

This causes ambiguous comments as reported in https://github.com/microsoftgraph/msgraph-sdk-dotnet/issues/2336

### Additional contract requirements

- When emitting deprecation information, code writers must resolve type-reference placeholders in the description template to the corresponding referenced type names rather than leaving the placeholders unresolved.
