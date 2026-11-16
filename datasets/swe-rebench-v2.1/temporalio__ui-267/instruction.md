[Bug] unable to convert filter expression, invalid StartTime format sent to server
### What are you really trying to do?

I am trying to run the temporal UI `temporalio/ui-server` v0.2.0 with `temporalio/temporal` v1.14.4.

### Describe the bug

The default `GET` request `/api/v1/namespaces/default/workflows?query=StartTime+%3E+%222022-01-30T01%3A43%3A45%2B02%3A00%22` returns a 500 error:

```
{
  "code": 2,
  "message": "invalid query: unable to convert filter expression: unable to convert values of comparison expression: StartTime only supports BETWEEN ... AND ... filter",
  "details": [
  ]
}
```

The origin of the error seems to be this commit: https://github.com/temporalio/temporal/commit/1e191789e37069157e204ad3d72db33e4da9fa71

### Additional contract requirements

- For a duration-valued `timeRange`, generate a `StartTime BETWEEN "<start>" AND "<end>"` query, where `<end>` is 24 hours after the current time, formatted as an ISO timestamp. When the current time is `2020-01-01T00:00:00Z` and the duration is 24 hours, the query must be exactly `StartTime BETWEEN "2019-12-31T00:00:00Z" AND "2020-01-02T00:00:00Z"`.
