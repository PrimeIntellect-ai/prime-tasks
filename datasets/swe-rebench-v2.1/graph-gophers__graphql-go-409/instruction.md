Interface inline fragment on union types results in panic.
## Error
Given:
```
interface Node {
  id: ID!
}

type A implements Node {
  id: ID!
  a: String!
}

type B implements Node {
  id: ID!
  b: String!
}

type C implements Node {
  id: ID!
  c: String!
}

union ABC = A | B | C

query {
  search(input: InputType!): ABC
}
```
If I make the following query to this mock api:
```
{
  search(input: { ... }) {
    ... on A {
      a
    }
    ... on B {
      b
    }
    ... on C {
      c
    }
    ... on Node {
      id
    }
  }
}
```
I get a panic error that Node does not implement ABC, originating from the following line of code: https://github.com/graph-gophers/graphql-go/blob/bb9738501bd42a6536227b96068349b814379d6e/internal/exec/selected/selected.go#L170

## Expected
I expect the Node inline fragment to resolve just fine, because A) relay makes queries of this nature via its api, and B) each type in the union implements the Node interface.

## Probable source of the error
Looking through the code I can see - correct me if I'm wrong - that the type assertion is only checking for possible types for the union. [HIDDEN]

### Update
I've decided to just make all my union types into interface types for the time being.

### Additional contract requirements

- When a query applies an inline fragment on an interface to a value returned through a union, the fragment must be applicable for a concrete union member that implements that interface. Its selected fields must resolve normally without panicking.
