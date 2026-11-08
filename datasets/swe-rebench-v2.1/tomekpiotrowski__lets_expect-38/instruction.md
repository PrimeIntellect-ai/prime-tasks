Use commas instead of semis in `when` variable declarations

### Additional contract requirements

- `when` accepts one or more assignments of the form `identifier = expression`, separated by commas, for example `when(a = 1, b = 2)`. An expression may itself contain commas, for example `when(array = [1, 2, 3])`.
- Assignments must be separated by commas. Omitting a comma, for example by separating assignments with a semicolon, is a syntax error and is rejected at compile time.
- At least one assignment is required. Invoking `when` with no assignments, for example `when()`, is a syntax error and is rejected at compile time.
