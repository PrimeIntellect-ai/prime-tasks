feature: Enhance unused Jobs discovery
Following [#283](https://github.com/yonahd/kor/pull/283), we added another indication for unused Jobs for Job that had reached BackoffLimit and failed.

Add the following indications to enhance the discovery:
1. Jobs that failed with `DeadlineExceeded`.
2. Job that failed with [FailedIndexes](https://kubernetes.io/docs/concepts/workloads/controllers/job/#backoff-limit-per-index) which is another type of BackoffLimit.
3. Suspended Jobs.

### Additional contract requirements

- Return the discovered unused Jobs in this order: `test-job2`, `test-job4`, `test-job5`, `test-job6`, `test-job7`, `test-job8`.
