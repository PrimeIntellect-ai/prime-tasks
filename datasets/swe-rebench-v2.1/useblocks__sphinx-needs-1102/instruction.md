Custom column titles in needtable does not work
Custom column titles in needtable does not work if the `needs_extra_options` has special characters like "-".

The following, for example, prints an empty "Description" column.

```rst
.. needtable::
   :filter: id.startswith("REQ_ID")
   :columns: id;title;status-desc as "Description";status
```

The following works:

```rst
.. needtable::
   :filter: id.startswith("REQ_ID")
   :columns: id;title;status-desc;status
```
