Creating a column affinity based on a string does not produce the correct affinity
E.g. take the example table definition from the `TestHelper`: https://github.com/stephencelis/SQLite.swift/blob/f1bee07ea9aa304d7e7024e759c4a031672c8732/Tests/SQLiteTests/TestHelpers.swift#L22-L31

According to [`3.1. Determination Of Column Affinity`](https://www.sqlite.org/datatype3.html#determination_of_column_affinity) the affinity of a column is based on the declared type. With the "parsing" following a set of five rules (see linked page).

So for the above table definition, the column affinity should be:

* `id` -> rule 1: `INTEGER` :white_check_mark:
* `email` -> rule 2: `TEXT` :white_check_mark:
* `age` -> rule 1: `INTEGER` :white_check_mark:
* `salary` -> rule 4: `REAL` :white_check_mark:
* `admin` -> rule 5: `NUMERIC` :x:
* `manager_id` -> rule 1: `INTEGER` :white_check_mark:
* `created_at` -> rule 5: `NUMERIC` :x:

but the affinity is incorrect for the following columns: `admin` and `created_at` (`TEXT` instead of `NUMERIC`).

See https://github.com/stephencelis/SQLite.swift/blob/f1bee07ea9aa304d7e7024e759c4a031672c8732/Tests/SQLiteTests/Schema/SchemaReaderTests.swift#L17-L57


A possible solution is to create the `Affinity` and implement the 5 rules, e.g. like here: https://github.com/stefansaasen/SQLite.swift/commit/fabbe8c0995aeddf343b8de949777e3e7aea5ea4

There is one important thing to consider here, the default affinity for declared types that are not covered is now `NUMERIC` instead of `TEXT`. E.g. with the gotcha mentioned here: https://www.sqlite.org/datatype3.html#determination_of_column_affinity

> And the declared type of "STRING" has an affinity of NUMERIC, not TEXT

Should probably considered to be a breaking change.

P.S.: Happy to create a PR if the approach in the commit linked above is acceptable.

## Build Information

- Include the SQLite.swift version: 0.14.1
- Mention Xcode and OS X versions affected: Xcode `14.3` and macOS Ventura `13.4`
- How do do you integrate SQLite.swift in your project: Swift Package manager

### Additional contract requirements

Column affinity is determined by parsing the column's declared type string, matching case-insensitively. The five rules are applied to the declared type string in order:

- A declared type containing `INT` has `INTEGER` affinity.
- A declared type containing `CHAR`, `CLOB`, or `TEXT` has `TEXT` affinity.
- A declared type containing `BLOB` has `BLOB` affinity.
- A declared type containing `REAL`, `FLOA`, or `DOUB` has `REAL` affinity.
- A declared type containing none of the above has `NUMERIC` affinity.
