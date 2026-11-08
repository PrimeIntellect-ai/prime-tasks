How to add params for indexing document data
I am using injest-attachment plugin for ES and i want to index data(as shown below)

PUT my_index/my_type/my_id?**pipeline=attachment**
{
  "data": "e1xydGYxXGFuc2kNCkxvcmVtIGlwc3VtIGRvbG9yIHNpdCBhbWV0DQpccGFyIH0="
}

how we can use the param(pipeline=attachment) with the jest plugin to index same data?

### Additional contract requirements

- Add a public constant `Parameters.PIPELINE` in `io.searchbox.params.Parameters` whose value is `"pipeline"`.
- When indexing a document, the pipeline parameter is sent as a query parameter (for example `?pipeline=attachment`).
- When indexing documents in a bulk request, a pipeline set on an individual index action is applied to that action.
