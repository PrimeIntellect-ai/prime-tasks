incorrect behaviour of SchemaUtils.create in a certain scenario involving composite foreign keys
in case there are two tables (parent and child), with the child table referring the parent by the means of a composite foreign key **only**, the reference is not taken into account by the call `SchemaUtils.create` and, subsequently, by `SchemaUtils.sortTablesByReferences`

this causes the SchemaUtils to try to create the child table first, resulting in an SQL error:
`CREATE TABLE IF NOT EXISTS child ..., CONSTRAINT fk_name FOREIGN KEY (col1, col2) REFERENCES parent(col1 col2) ...`
`[42102-199]. Statement(s): ...`
`Table parent not found`
(using H2 in this instance)

the problem is actual as of 0.41.1
