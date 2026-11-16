BlockStringValues do not strip common indentation
Multiline string (Block String) support leaves common leading indentation on each line, resulting in unexpected indentation in documentation. This has impacts such as incorrectly formatting when rendered in CommonMark (like in GraphiQL), as subsequent lines after the first end up being treated as code blocks.

The spec calls out the need to strip this leading indentation: https://graphql.github.io/graphql-spec/June2018/#sec-String-Value

> Since block strings represent freeform text often used in indented positions, the string value semantics of a block string excludes uniform indentation and blank initial and trailing lines via BlockStringValue().

https://github.com/graphql/graphql-js implements this, and refers to that section of the spec: https://github.com/graphql/graphql-js/blob/master/src/language/blockString.js#L3:L34

I have verified this behaviour, comparing `graphql-js` and `graphql-go` for this basic schema:

```
  schema {
     query: Query
  }
  type Query {
    """
    First line of docs.

    Second line of docs.

        ... code example ...
        ... code example ...
        ... code example ...
    """
    hello: String!
  }
```

For the `hello` field `graphql-js`, the introspection query returns the `description` value as:

```
First line of docs.\n\nSecond line of docs.\n\n    ... code example ...\n    ... code example ...\n    ... code example ...
```

While `graphql-go` returns:

```
First line of docs.\n\n    Second line of docs.\n\n        ... code example ...\n        ... code example ...\n        ... code example ...
```
