additional Join functionality
- It would be a nice convenience function just to specify a string or list of strs if the column(s) to join on are the same in both tables. e.g. from_(t1).join(t2).on('c1')

- it's not clear how I can construct a join USING clause "... from t1 join t2 USING (c1, c2)"

i'm happy to contribute if this is not yet available but you think would be helpful

I'm sorry the docs don't show a preferred method of getting in touch. please suggest most appropriate communication channel. You can look me up as "CJ Lee" from London on linkedin

P.S. love this package thanks for this

### Additional contract requirements

- The object returned by `Query.join(...)` provides a method named `on_field` that accepts one or more column names as positional string arguments. It is a shortcut for joining when the named columns exist with the same name in both the FROM table and the joined table.
- Calling `on_field` with columns `"foo"` and `"bar"` produces an ON condition equating each named column between the two tables (`"abc"."foo"="efg"."foo" AND "abc"."bar"="efg"."bar"`), and the query is returned so it can keep being chained (e.g. `.select(...)`).
- A single column name produces a single equality, and a join followed by another join can each use their own `on_field` call.
- Calling `on_field` without any column name raises `JoinException`.
