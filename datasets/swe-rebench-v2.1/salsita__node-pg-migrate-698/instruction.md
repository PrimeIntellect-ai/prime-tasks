Dollar-string escaping fails on Cockroachdb
Escaping strategy fails on Cockroachdb.

https://github.com/salsita/node-pg-migrate/blob/8489b732aefab12252b60c99f0bc7a5af776fdad/src/utils.ts#L39

See https://github.com/cockroachdb/cockroach/issues/54676.

### Additional contract requirements

- When escaping a value that does not contain `$pga$`, use `$pga$` as the dollar-quote delimiter; for example, `#escape_me` must be rendered as `$pga$#escape_me$pga$`.
