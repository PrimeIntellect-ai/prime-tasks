Update postgres and mysql with NUMERIC
In spanner/v1.10.0, we have supported NUMERIC type. So we would like to update postgres and mysql with NUMERIC type.

### Additional contract requirements

- PostgreSQL and MySQL NUMERIC and DECIMAL columns must be converted to Spanner's NUMERIC type.
- When converting MySQL NUMERIC values, represent them as strings with exactly 9 digits after the decimal point; for example, `5.44444` must be represented as `5.444440000`.
- When converting PostgreSQL NUMERIC values, represent them as strings with exactly 9 digits after the decimal point; for example, `444.9876` must be represented as `444.987600000`.
