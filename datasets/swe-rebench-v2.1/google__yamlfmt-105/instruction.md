Doublestar excludes doesn't seem to work:
I have this:

```
doublestar: true
exclude:
  - **/templates/**
formatter:
  type: basic
  indent: 2
  include_document_start: true
```

And I am doing this to prevent the yamlfmt from formatting my `templates/` folder that are in my helm charts, since it messes everything up.

However, it keeps complaining that:
`2023/03/24 14:38:02 yaml: line 3: did not find expected alphabetic or numeric character`.

So I put line 3 in quotes `"- **/templates/**"` and now the error goes away.  However, it doesn't respect my excludes and continues to format things in the `templates/` folder.
