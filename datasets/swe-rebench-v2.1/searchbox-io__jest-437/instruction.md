Add reindex API
[reindex API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-reindex.html) is a powerful new elasticsearch feature since version 2.3.
This would be great to add support for this feature in Jest API !

### Additional contract requirements

Add a public class `Reindex` in package `io.searchbox.indices.reindex` that represents the Elasticsearch reindex action, together with a nested public builder `Reindex.Builder`.

- `Reindex.Builder(Object source, Object dest)` creates a builder holding the source and destination specifications.
- `Reindex.Builder.conflicts(String conflicts)` sets the optional `conflicts` payload field and returns the builder.
- `Reindex.Builder.waitForCompletion(boolean waitForCompletion)` sets the `wait_for_completion` query parameter and returns the builder.
- `Reindex.Builder.waitForActiveShards(int waitForActiveShards)` sets the `wait_for_active_shards` query parameter and returns the builder.
- `Reindex.Builder.timeout(long timeout)` sets the `timeout` query parameter and returns the builder.
- `Reindex.Builder.requestsPerSecond(double requestsPerSecond)` sets the `requests_per_second` query parameter and returns the builder.
- `Reindex.Builder.build()` returns the constructed `Reindex` action.
- `Reindex.getRestMethodName()` returns `POST`.
- `Reindex.getURI()` returns the reindex endpoint `/_reindex`, followed by the configured query parameters.
- `Reindex.getData(com.google.gson.Gson gson)` returns the JSON request body containing the `source` and `dest` specifications and, when set, the `conflicts` value.

When `waitForCompletion(true)`, `waitForActiveShards(1)`, `timeout(5000L)` and `requestsPerSecond(5d)` are set, `getURI()` returns exactly `/_reindex?wait_for_completion=true&wait_for_active_shards=1&timeout=5000&requests_per_second=5.0`.

With source `{"index":"sourceIndex"}`, dest `{"index":"destIndex"}` and `conflicts("proceed")` set, `getData(gson)` returns a JSON object whose `source` member is `{"index":"sourceIndex"}`, whose `dest` member is `{"index":"destIndex"}` and whose `conflicts` member is `"proceed"`.
