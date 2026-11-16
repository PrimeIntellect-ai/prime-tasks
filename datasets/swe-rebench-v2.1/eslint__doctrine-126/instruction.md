`@param {string} employees[].name` is parsed incorrectly
This example comes from http://usejsdoc.org/tags-param.html#parameters-with-properties

Expected result:

```
{
  title: "param",
  name: "employees[].name",
  description: undefined,
  type: ...
}
```

Actual result:

```
{
  title: "param",
  name: "employees",
  description: "[].bar",
  type: ...
}
```
