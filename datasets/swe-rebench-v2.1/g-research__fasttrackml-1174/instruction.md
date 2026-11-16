Allow dot syntax when searching tags via Aim UI query syntax
Searching for runs or metrics via run tags can currently be done like this in the Aim UI:

```python
run.tags["my.tag"] == "something"
```

Given that the query field autocomplete suggests bracket syntax for tags containing `.` or `-`, this is totally fine. However, tags that don't contain characters like that get (rightfully) completed with dot syntax, for which we send back a syntax error. Here is an example of a query that _should_ work but doesn't yet:

```python
run.tags.my_tag == "something"
```
