Proposal: modify metrics endpoints to make more similar
To define data sources we have the following:

- **HTTP**:
  - URL: `http://iter8.default:8080/httpDashboard`
  - query string: `namespace=ns&experiment=test_name`
- **gRPC**:
  - URL: `http://iter8.default:8080/grpcDashboard`
  - query string: `namespace=ns&experiment=test_name`
- **A/B/n**:
  - URL: `http://iter8.default:8080/metrics`
  - query string: `application=ns%2Fapp`

I wondered if we wanted to regularize this:
- For A/B/n use `abnDashboard` instead of `metrics` as the endpoint
- For A/B/n change structure of query string to be `namespace=ns&application=app`
- change `experiement` to `test` or `performance_test`
- Not sure how to make the second parameter the same; but there is no real need to

### Additional contract requirements

- Serve the A/B/n dashboard at `/abnDashboard` instead of `/metrics`.
- Identify an A/B/n dashboard application using separate `namespace` and `application` query parameters.
- HTTP and gRPC dashboards must identify the test using either `test` or `performance_test` rather than `experiment`, while continuing to use `namespace`. With `namespace` supplied, either supported key must be accepted independently; both keys must not be required together.
