[FORMATTING] GBQ @@error.message not supported
```
BEGIN
select 1/0;
EXCEPTION WHEN ERROR THEN
SELECT @@error.message;
END;
```
Unable to format SQL: Error: Parse error: Unexpected "@@error.me" at line 4 column 8

This code is for BigQuery.
