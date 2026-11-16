fortio access log doesn't show success vs error requests

### Additional contract requirements

The access log must record, for every request, whether the request succeeded
and an optional details string (for HTTP, the numeric response code). The
runner results must additionally expose a histogram of the durations of the
failed requests.

Public API:

- `periodic.Runnable.Run(tid int) (status bool, details string)` in package
  `fortio.org/fortio/periodic`: returns `true` for a normal/successful run and
  `false` otherwise, with `details` an optional string that is persisted to the
  access log.
- `periodic.AccessLogger.Report(thread int, time int64, latency float64, status bool, details string)`
  in package `fortio.org/fortio/periodic`: persists the request status and the
  optional details in the access log.
- `periodic.RunnerResults.ErrorsDurationHistogram` in package
  `fortio.org/fortio/periodic`: a histogram of the durations of the requests
  whose `Run` returned `false`.
- `fhttp.HTTPRunnerResults.Run(t int) (bool, string)` in package
  `fortio.org/fortio/fhttp`: returns `true` and the details `"200"` only when
  the HTTP response code is 200, otherwise `false` and the numeric status code
  as a string.


- In both JSON and Influx access-log formats, encode request status using the boolean literals `true` and `false`, and encode details as a quoted string (for HTTP, e.g. `"200"` or `"555"`).
