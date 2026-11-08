Display DOUBLES  with a decimal point
Doubles with `.0` decimal is currently printed as `integer` it should be displayed as double.
```SQL
CREATE TABLE foo (a DOUBLE NOT NULL, b DOUBLE NOT NULLl);
INSERT INTO foo VALUES {"a": 2.0, "b": 3.1};
SELECT * from foo;
{
  "a": 2,
  "b": 3.1
}
```

expected

```SQL
SELECT * from foo;
{
  "a": 2.0,
  "b": 3.1
}
```

### Additional contract requirements

- An integral-valued double of 10 must be rendered exactly as `10.0`.
