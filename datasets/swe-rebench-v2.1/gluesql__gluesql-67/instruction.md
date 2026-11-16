NULL + 1 should be NULL
https://github.com/gluesql/gluesql/pull/59#issuecomment-687709531

Current:
`NULL + 1 => 1`

Expected:
`NULL + 1 => NULL`

### Additional contract requirements

- NULL propagation applies to addition in either operand order: both `NULL + 1` and `1 + NULL` evaluate to NULL.
- The same NULL propagation applies when the NULL operand comes from a column value, e.g. `id + 1` (and `1 + id`) evaluate to NULL when `id` is NULL.
