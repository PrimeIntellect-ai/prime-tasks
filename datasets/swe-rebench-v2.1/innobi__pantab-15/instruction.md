Append Mode Support
After discussing with @rhelenius on the Tableau forums I think need to add support for Append Mode with Hyper Extracts. This can support delta processes and potential chunking of datasets into Hyper.

Some consideration points:

  * The meaning of "Append" can be ambiguous; in some contexts append may refer to adding a Table to an Extract / Schema and in other contexts this may mean appending to an existing table
  * Need to be cognizant of what the Hyper API exposes as terminology at the database level; those terms are:
    * CREATE: Create the database. Will fail if it already exists
    * CREATE_AND_REPLACE: Create the database. If already exists, drop the old one first
    * CREATE_IF_NOT_EXISTS: Create the database if it does not exist
    * NONE: Do not create the database. Will fail if it already exists

I'll jot some more thoughts down later, but we may want to offer similar enumerations for Table creation and add as a keyword argument to the existing functions, or maybe even just re-purpose the enum already exposed by Hyper

### Additional contract requirements

- Add a public function `frame_to_hyper(df, database, *, table, table_mode="w")` in the `pantab` package. It writes `df` to the Hyper extract at `database`. With `table_mode="w"` (the default) the target table is recreated; with `table_mode="a"` rows are appended to an existing table, and the table is created if it does not yet exist.
- Add a public function `frames_to_hyper(dict_of_frames, database, table_mode="w")` in the `pantab` package. It writes each DataFrame in `dict_of_frames` to its corresponding table in the Hyper extract. With the default mode, each table is recreated; with `table_mode="a"` rows are appended to existing tables, and the table is created if it does not yet exist. `table_mode` may be supplied as the third positional argument or by keyword.
- Both functions raise `ValueError` with the message `'table_mode' must be either 'w' or 'a'` when `table_mode` is neither `"w"` nor `"a"`.
- When `frame_to_hyper` is called with `table_mode="a"` and the target table's column definitions differ from those of `df`, a `TypeError` is raised whose message begins with `Mismatched column definitions:`.
