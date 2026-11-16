`extend input` fails to extend
Given this schema, the second definition overwrites the first rather than extending it.

```
input InputType {
  fieldA: String
}

extend input InputType {
  fieldB: String
}
```
