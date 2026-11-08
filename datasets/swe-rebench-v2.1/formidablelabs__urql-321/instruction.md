Typenames are being unnecessarily added
Typenames are added to selections without checking if a typename node is already present.

Example query:
```
{
  todos {
    id
    text
    complete
    __typename
    __typename
    __typename
  }
  __typename
  __typename
  __typename
}
```
