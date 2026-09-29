The repairs retain every scored case and its exported ID.

- Scope a working-directory change to the fixture that needs it.
- Use transactions for bulk setup inserts; reset setup state on reruns.
- Keep session-database tests in original source order on the same xdist worker. Map JUnit scheduler suffixes back to the exact pinned metadata IDs after execution; metadata includes both suffixed and unsuffixed IDs.
- Give self-contained schema scenarios a fresh database rather than inheriting unrelated tables and triggers.
- Restore SQLite's explicit database reset before altertab scenario 13.
- Restore the original successful CTE/view semantics for altertab scenario 29. The generated Python tests had interpreted the SQL result `1` as an error exit code and lost later SELECT/schema assertions. Each repaired case supplies the required schema independently, including setup from the ignored generated setup case. Assertions verify successful execution, query result `1`, or the exact renamed view SQL as appropriate.

Source for the scenario 13 and 29 corrections:
https://github.com/sqlite/sqlite/blob/839433d4571382d1c4f4bfca815de1e8f03ac015/test/altertab.test#L397
https://github.com/sqlite/sqlite/blob/839433d4571382d1c4f4bfca815de1e8f03ac015/test/altertab.test#L797
