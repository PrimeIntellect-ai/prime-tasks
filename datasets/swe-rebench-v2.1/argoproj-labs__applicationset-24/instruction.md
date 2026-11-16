Application labels are not templated by cluster generator
Per the [`clusters.yaml` example](https://github.com/argoproj-labs/applicationset/blob/master/examples/clusters.yaml), we should be able to reuse labels from the cluster secret in the application template. This does not currently work.
