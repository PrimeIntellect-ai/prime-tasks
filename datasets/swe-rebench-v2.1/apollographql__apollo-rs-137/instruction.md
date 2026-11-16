How to get field names from selection set?
<!--
  Before opening a new issue, please search existing issues: https://github.com/apollographql/apollo-rs/issues
-->

## Description

Given the query below, I'd like to know how to extract the field names (`id`, `field1`, `field2`) from the selection set.

```
let query = r#"query SomeQuery(
  $param1: String!
  $param2: String!
) {
  item1(
    param1: $param1
    param2: $param2
  ) {
    id
    field1
    field2
    field3 {
      field1
      field2
    }
  }
}
```
