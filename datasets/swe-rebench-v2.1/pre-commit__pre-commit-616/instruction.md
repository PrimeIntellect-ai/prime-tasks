Feature request : add a "fail fast" configuration entry
Here is my use case:
- I have integration tests (in Java + with protractor) that are costly to execute (in term of execution time)
- when earlier hooks detect issues with the code (e.g. `eslint` checks), I don't want to execute my integration tests until I've fixed those errors

Btw, I don't ask to change the current behaviour, but could you develop on the reasons behind the design decision to run all tests, indifferently of their outcome ? What are the benefits ?

### Additional contract requirements

- The new configuration entry is named `fail_fast` and defaults to `false` (disabled), so the existing behaviour of running every hook is preserved unless the entry is explicitly enabled.
