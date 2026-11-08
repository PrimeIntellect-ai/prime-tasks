Parenthesis around column arithmetic operation
when i parsed the sql like
`	insert into target1 (code,p,lsh)
       select code,(payment_standard - fee_tot) ,lsh
       from source1
`
i got the result
(Column: <default>.source1.code, Column: <default>.target1.code)



but i expect the result like

(Column: <default>.source1.code, Column: <default>.target1.code)
(Column: <default>.source1.payment_standard , Column: <default>.target1.p)
(Column: <default>.source1.fee_tot , Column: <default>.target1.p)
(Column: <default>.source1.lsh, Column: <default>.target1.lsh)

### Additional contract requirements

- For `INSERT INTO tab1 SELECT (col1 + col2) FROM tab2`, report lineage from both `tab2.col1` and `tab2.col2` to the destination column `(col1 + col2)` in `tab1`.
