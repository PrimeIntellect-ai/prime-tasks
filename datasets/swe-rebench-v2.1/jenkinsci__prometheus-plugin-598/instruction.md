jenkins_builds_last_build_result_ordinal is missing in the  prometheus
### Jenkins and plugins versions report

<details>

  <summary>Environment</summary>

  <!-- Paste your environment details below -->
  ```
Jenkins: 2.414.2
prometheus:2.3.2
metrics:4.2.18-442.v02e107157925
  ```

</details>


### What Operating System are you using (both controller, and any agents involved in the problem)?

OS: Linux

### Reproduction steps

We have observed changes in Prometheus version 2.3.2. The last build results ordinal gauge doesn't track the status of the running job. Previously, we were using Prometheus version 2.2.3 and didn't encounter such issues. Can someone help us with this?

### Expected Results

 The last build results ordinal gauge should track the status of the running job

```
# TYPE default_jenkins_builds_last_build_result_ordinal gauge
default_jenkins_builds_last_build_result_ordinal{jenkins_job="content/job-X.Y.Z-rhel8",repo="NA",buildable="true",} -1.0"
```


### Actual Results

we see the build job in default_jenkins_builds_last_build_result_ordinal gauge after it gets completed

```
# TYPE default_jenkins_builds_last_build_result_ordinal gauge
default_jenkins_builds_last_build_result_ordinal{jenkins_job="content/job-X.Y.Z-rhel8",repo="NA",buildable="true",} 1.0"
```

### Anything else?

_No response_

### Are you interested in contributing a fix?

_No response_
