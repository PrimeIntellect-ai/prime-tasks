`row._mapping` is broken after pagination
Already found the culprit at https://github.com/djrobstep/sqlakeyset/blob/aa097fc055322ad0773d619115640f7b005152c8/sqlakeyset/sqla20.py[HIDDEN]

Instead of `key -> col value` mapping, `Row` wants [HIDDEN] mapping.

I'm running SQLAlchemy 2.0.23 and I have no idea if something has changed after 2.0.11.

### Additional contract requirements

- For SQLAlchemy 2.0.23, rows returned by pagination for both ORM and Core queries must expose `_mapping` with column keys associated with the same values as the corresponding unpaginated rows.
