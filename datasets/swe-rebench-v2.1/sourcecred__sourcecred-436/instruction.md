Refactor GitHub testing to export demo data methods
Right now GitHub test code directly requires the demodata in several places. We should abstract this into a little utility module that ensures the data never gets state pollution, and is provided with the correct typing, as suggested by @wchargin here: https://github.com/sourcecred/sourcecred/pull/428#discussion_r198664313

### Additional contract requirements

- Add a module at `src/v3/plugins/github/example/example.js` that exports:
  - `exampleData()`: returns a fresh deep copy of the example GitHub GraphQL response data. Each call returns an independent copy, so mutating the returned value never affects any other copy.
  - `exampleRelationalView()`: returns a `RelationalView` built from the example data.
  - `exampleGraph()`: returns a `Graph` built from the example relational view.

- The Flow return types exposed by `exampleData()`, `exampleRelationalView()`, and `exampleGraph()` must be `GithubResponseJSON`, `RelationalView`, and `Graph`, respectively.
