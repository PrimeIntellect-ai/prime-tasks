Fails to parse BigQuery UDF with "ANY TYPE" parameters
EDIT: The "proper" name for this pattern is "Templated, SQL UDF Parameters", which can be further elaborated in the BQ Docs: https://cloud.google.com/bigquery/docs/user-defined-functions#templated-sql-udf-parameters

trying to parse this simple function like this:
```
fn main() {
    let sql = "
CREATE TEMP FUNCTION my_function(are_map ANY TYPE)
AS (
  (SELECT 1)
);
    ";

    let ast = Parser::parse_sql(&BigQueryDialect, sql).unwrap();
    for stmt in &ast {
        println!("{:?}", stmt);
    }
}
```

Yields this error:
```
thread 'main' panicked at src/main.rs:18:56:
called `Result::unwrap()` on an `Err` value: ParserError("Expected: ), found: TYPE at Line: 2, Column: 46")
```
I can try to have a look at this , seems relatively straightforward to fix!
