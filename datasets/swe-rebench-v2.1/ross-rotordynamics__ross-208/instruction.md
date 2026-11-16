Error when trying to load bearing element from xl file
I tried to import an xl file but I was not able to.
I have added this file to our tests/data folder (see https://github.com/ross-rotordynamics/ross/commit/8eedac2e4f505a13eac5abe0f11599d76c7b5882).
This file should be used to test the .from_table() method implemented
for bearings and seals. Tests should be similar to those that we have
for importing shaft elements from an xl file.

### Additional contract requirements

The table-import method must continue to accept CSV input. When table values are NaN, loading must warn the user and replace those values with zero.
