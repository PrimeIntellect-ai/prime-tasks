Provide clearer error for incorrect pagination component usage
**Is your feature request related to a problem? Please describe.**
Recently while integration flop_phoenix into my application, I made a subtle error: I attempted to use `Flop.Phoenix.pagination` with a cursor-paginated result set. The error I got was `ArithmeticError: bad argument in arithmetic expression` which was not super-helpful.

**Describe the solution you'd like**
Ideally, the pagination component would detect that the provided `meta` is not of the correct type and raise an exception or provide some other clear indication of how to correct the problem.

**Describe alternatives you've considered**
I could document the error and give directions, but it seems better to provide that as an exception rather than expecting busy developers to read the fine print.

**Additional context**
I already have a PR written, but I wanted to follow proper procedure. I'll open it as soon as I finish typing up the issue.

### Additional contract requirements

When the page-based pagination component receives cursor-paginated metadata, it must detect the mismatch and clearly indicate that cursor-based pagination is the appropriate alternative.
