GraphQLTypeReference instead of proper GraphQlInputObjectType during runtime (Directive wiring) on NonNull Input types
My team is using the graphql-java-extended-validation library and we identified that the validations would not execute when we add the validation on a NonNull input type. Initially, we thought this would be a bug there, but now we identified that this is happening because this validation library executes over the directive wiring, and sadly at that level of execution GraphQLArguments that are NonNull hasn't the proper GraphQLInputObjectType definition for it, just has the `GraphQLTypeRefernce` for that type, which will later be replaced on GraphQLSchema building method. But we need the proper InputObject Definition at runtime, at Directive Wiring.
I created a test case to illustrate this issue and also pushing a PR with the solution we found to have this reference properly set at runtime without falling into infinity recursion.


Test Case to illustrate the issue:
```groovy
def "NonNull and nullable arguments returning it's GraphQLInputObjectType "() {
        when:
        GraphQLSchema schema = SchemaParser.newParser().schemaString('''\
                    type Query {
                        testNonNullable(filter: Filter!): Boolean
                        testNullable(filter: Filter): Boolean
                    }
                    input Filter {
                        filter: String
                    }
                '''.stripIndent())
                .resolvers(new GraphQLQueryResolver() {
                    boolean testNonNullable(Filter filter) { false }
                    boolean testNullable(Filter filter) { false }
                })
                .directiveWiring(new SchemaDirectiveWiring(){
                        GraphQLArgument onArgument(SchemaDirectiveWiringEnvironment<GraphQLArgument> environment) {
                            switch (environment.getElement().type.class) {
                                case GraphQLNonNull:
                                    assert (environment.getElement().type as graphql.schema.GraphQLNonNull).wrappedType.class == GraphQLInputObjectType
                            }
                            return environment.getElement()
                        }})
                .build()
                .makeExecutableSchema()

        then:
        GraphQLArgument testNonNullableArgument = schema.getObjectType("Query")
                .getFieldDefinition("testNonNullable")
                .arguments.first()
        GraphQLArgument testNullableArgument = schema.getObjectType("Query")
                .getFieldDefinition("testNullable")
                .arguments.first()
        testNonNullableArgument.type.class == graphql.schema.GraphQLNonNull
        (testNonNullableArgument.type as graphql.schema.GraphQLNonNull).wrappedType.class == GraphQLInputObjectType
        testNullableArgument.type.class == GraphQLInputObjectType
    }
```
