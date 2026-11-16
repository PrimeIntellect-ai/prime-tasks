Set schema description for introspection when instantiating GraphQLSchema
<!-- ⚠️ Please ensure you are requesting the feature in the correct repository! -->

__I want to suggest an idea and checked that ...__

- [X] ... to my best knowledge, my idea wouldn't break something for other users
- [X] ... the documentation does not mention anything about my idea
- [X] ... there are no open or closed issues that are related to my idea

## Description

The GraphQL Specification provides for introspection of the [Schema description](https://spec.graphql.org/October2021/#sec-The-__Schema-Type).

`graphql-java` allows for a description to be provided in the `SchemaDefinition` [constructor](https://github.com/graphql-java/graphql-java/blob/9e53ca9bae1bc4f15a3de96d96a1b2b94ffd5031/src/main/java/graphql/language/SchemaDefinition.java#L38).

`graphql-java-tools` does not currently pass this through when instantiating `GraphQLSchema`.

### Use Cases

To be able to describe a graph at schema level.
