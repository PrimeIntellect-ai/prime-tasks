expression returned using shouldIncludeExpression is not the original root expression
When an expression is returned it might be the typeSymbol https://github.com/styleguidist/react-docgen-typescript/blob/1a14c0edc609455a4c2766fa5eec68bc3b902d05/src/parser.ts#L304 which means that we cannot easily get the original root expression from it. Was this intended? I think it would be a lot more powerful if the original root expression was returned which would allow users to pull as much information as needed out of it.

My primary use case for this would be to be able to get default export names using it, which I cannot see an easy way to get this information from the type symbol which refers to the "FunctionComponent" type.

cc @TrevorBurnham

### Additional contract requirements

When `shouldIncludeExpression` is enabled, each parsed component result exposes its original source-level root expression through `rootExpression`, in addition to the existing component type expression. For a component exported as `React.memo(Jumbotron)`, this value must let callers obtain source information showing that wrapper expression and the component name; it need not use a particular TypeScript representation.
