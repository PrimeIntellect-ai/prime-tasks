Add passing checks count to the ConfigAuditReport summary
Currently we only have DANGER and WARNING counts in the ConfigAuditReport summary. We should display the number of passing checks as well.

```console
$ kubectl get configauditreports.aquasecurity.github.io -o wide
NAME               SCANNER   AGE   DANGER   WARNING
deployment-nginx   Polaris   28m   0        8
```
```console
$ kubectl get configauditreports.aquasecurity.github.io -o wide
NAME               SCANNER   AGE.  PASS   DANGER   WARNING
deployment-nginx   Polaris   28m   13     0        8
```

### Additional contract requirements

- In package `pkg/apis/aquasecurity/v1alpha1`, the `ConfigAuditSummary` type has an integer field `PassCount` serialized as `passCount`.
- The `ConfigAuditReport` custom resource definition (`ConfigAuditReportCRD` in package `pkg/apis/aquasecurity/v1alpha1`) exposes the pass count as an additional printer column named `Pass` whose value is read from `.report.summary.passCount`, so that `kubectl get configauditreports.aquasecurity.github.io -o wide` shows a `PASS` column.
