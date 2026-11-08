add scalar definitions to compiler's context
- add scalar definitions to database
- add validations for scalars
     - custom scalars must have a `@specifiedBy` directive
     - cannot have built-in directives defined

### Additional contract requirements

- Built-in scalar definitions must be rejected: redefining a built-in scalar
  (`Int`, `Float`, `Boolean`, `String`, `ID`) is reported as a
  `BuiltInScalarDefinition` error whose `message` is
  "Built-in scalars must be omitted for brevity" and whose `scalar` field holds
  the built-in scalar's name.
- A custom scalar that does not carry a `@specifiedBy` directive is reported as a
  `ScalarSpecificationURL` error whose `message` is
  "Custom scalars must provide a scalar specification URL via the @specifiedBy directive"
  and whose `scalar` field holds the scalar's name.
- Expose parsed scalar definitions through `ApolloCompiler::scalars() -> Arc<Vec<ScalarDefinition>>`.
  Each definition must expose its name through `ScalarDefinition::name() -> &str`
  and its attached directives through `ScalarDefinition::directives() -> &[Directive]`.
