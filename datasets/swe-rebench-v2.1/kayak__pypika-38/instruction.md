additional Join functionality
- It would be a nice convenience function just to specify a string or list of strs if the column(s) to join on are the same in both tables. e.g. from_(t1).join(t2).on('c1')

- it's not clear how I can construct a join USING clause "... from t1 join t2 USING (c1, c2)"

i'm happy to contribute if this is not yet available but you think would be helpful

I'm sorry the docs don't show a preferred method of getting in touch. please suggest most appropriate communication channel. You can look me up as "CJ Lee" from London on linkedin

P.S. love this package thanks for this

### Additional contract requirements

After selecting a join target with `join()`, callers can specify shared join-column names directly with `using()`, without constructing a field-to-field criterion. Pass one column name as a string, or pass multiple column names as separate string arguments. The resulting join SQL must contain a `USING` clause listing the requested columns.
