column lineages from boolean expression
I have problems with some queries which contain boolean expressions (exasol-db). I only use the LineageRunner(sql_statement).get_column_lineage()-function without the gui.

The column lineages ignore the second boolean field (IS_CASE_TWO).
```
CREATE VIEW VIEW_A AS
SELECT
    TABLE_ID,
    NUMBER_01 + NUMBER_02 > 0 AS IS_CASE_ONE,
    (NUMBER_01 + NUMBER_02 > 0 AND NUMBER_03 + NUMBER_04 <= 0) AS IS_CASE_TWO
FROM
    TABLE_A
```


It is possible the following query parse with version 1.3.3. This ignore the timestamp fields in boolean expressions.
```
CREATE VIEW VIEW_B AS
SELECT
    TABLE_ID,
    (
        FIRST_TIMESTAMP IS NOT NULL
        AND FIRST_TIMESTAMP >= TO_TIMESTAMP(ADD_DAYS(CURRENT_DATE, -100))
        AND OTHER_TIMESTAMP > TO_TIMESTAMP(ADD_YEARS(CURRENT_DATE, -7))
    ) AS IS_QUALIFIED
FROM
    TABLE_B
```
I get in version 1.3.4 to many column lineages, like TABLE_B.IS -> IS_QUALIFIED or TABLE_B.NOT NULL -> IS_QUALIFIED.
