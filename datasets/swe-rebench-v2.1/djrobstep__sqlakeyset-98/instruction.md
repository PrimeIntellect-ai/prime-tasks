SQLAlchemy 2 wrong type for column desc
Using Postgres and getting this error when I call `select_page` against core (not ORM):

```
  File "/Users/csantero/projects/example/.venv/lib/python3.10/site-packages/sqlakeyset/asyncio.py", line 84, in select_page
    return await core_get_page(s, selectable, per_page, place, backwards)
  File "/Users/csantero/projects/example/.venv/lib/python3.10/site-packages/sqlakeyset/asyncio.py", line 30, in core_get_page
    sel = prepare_paging(
  File "/Users/csantero/projects/example/.venv/lib/python3.10/site-packages/sqlakeyset/paging.py", line 196, in prepare_paging
    mapped_ocols = [find_order_key(ocol, column_descriptions) for ocol in order_cols]
  File "/Users/csantero/projects/example/.venv/lib/python3.10/site-packages/sqlakeyset/paging.py", line 196, in <listcomp>
    mapped_ocols = [find_order_key(ocol, column_descriptions) for ocol in order_cols]
  File "/Users/csantero/projects/example/.venv/lib/python3.10/site-packages/sqlakeyset/columns.py", line 429, in find_order_key
    ok = derive_order_key(ocol, desc, index)
  File "/Users/csantero/projects/example/.venv/lib/python3.10/site-packages/sqlakeyset/columns.py", line 370, in derive_order_key
    entity = desc["entity"]
KeyError: 'entity'
```

Python: 3.10.10
SQLAlchemy: 2.0.18
sqlakeyset: 2.0.1691149549
psycopg: 3.1.9

I've tried both AsyncEngine and Engine with psycopg 3. I also tried psycopg2 Engine and got the same result.

When I debug I can tell that `desc` is a dict, and not a `ColumnElement`:
```
"{'name': 'my_column', 'type': UUID(), 'expr': Column('my_column', UUID(), table=<my_table>)}"
```

[HIDDEN]

If this looks like the right approach then I'm happy to work up a PR, though I'm not quite sure how to produce a failing test case.

### Additional contract requirements

- For SQLAlchemy 2 Core queries, `select_page` must handle column-description mappings that lack an `entity` key without raising `KeyError`, while preserving paging by the selected ordering column.
