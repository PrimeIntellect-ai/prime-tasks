Failure to Handle Multiple Lineage Path for Same Column
Why holders.get_column_lineage return simple_paths which equal to one only? Are there any reasons?
In my case, i have a target column (i.e. with alias X) which is the result of a CASE construction, and all of those columns (A,B,C) are from same column and same table (i.e. BASE_TABLE.Z), so result of nx.all_simple_paths returns the next paths:
1) BASE_TABLE.Z->A->X
2) BASE_TABLE.Z->B->X
3) BASE_TABLE.Z->C->X

But get_column_lineage not return any one, the reason is the following lines:
[HIDDEN]

(simplified example)
CASE
when JOIN_TABLE_1.A not null JOIN_TABLE_1.A
when JOIN_TABLE_2.B not null JOIN_TABLE_2.B
else JOIN_TABLE_3.C
END as X
JOIN SELECT Z as A FROM BASE_TABLE as JOIN_TABLE_1
JOIN SELECT Z as B FROM BASE_TABLE as JOIN_TABLE_2
JOIN SELECT Z as C FROM BASE_TABLE as JOIN_TABLE_3

Thank you in advance!

### Additional contract requirements

- When a source column can reach a target column by more than one valid lineage path, report its lineage rather than omitting it solely because multiple paths exist.
