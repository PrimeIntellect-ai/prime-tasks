Problem with SELECT CAST(CASE WHEN ...END AS DECIMAL(M,N)) AS col_name
Sorry for this problem, but if statement is like:
SELECT CAST(CASE WHEN ...,
                               WHEN ...,
                               END AS DECIMAL(M, N)) AS col_name
FROM ...
the result is:
<default>table_name.col_name -> decimal
I don't know how to deal with this statement, or could I cut 'CAST’ function for analysis?
