Cannot parse negative numbers
For example, this query:
```
select to_id, date from edges where from_id = -1 and edge_type = 3 order by id desc
```

leads to:
```
Cannot lex instruction. Syntax error near -1 and edge_type = 3 order by id desc
```
