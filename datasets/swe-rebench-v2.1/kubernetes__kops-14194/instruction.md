All instancegroups must fail before kops exits on rolling update
/kind bug

**1. What `kops` version are you running? The command `kops version`, will display
 this information.**

1.20.3

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**

1.20.15

**3. What cloud provider are you using?**

AWS

**4. What commands did you run?  What is the simplest way to reproduce this issue?**

```
$ kops rolling-update cluster my-cluster.io --state s3://plaid-kops --master-interval 5m0s --node-interval 5m0s --post-drain-delay 5s --validation-timeout 15m0s --yes
```

**5. What happened after the commands executed?**

The rolling update went appropriately! But, we use an AWS IAM role in order to control permissions to run kops commands. Some of the clusters are rather large, so due to https://github.com/kubernetes/kops/issues/5130 we end up waiting for kops to fail with a specific error, refresh the role and then re-run the command.

When this happens we see the following logs:

<details>

```
[2022-08-24T16:07:58.971Z] E0824 16:07:53.703940     321 instancegroups.go:457] Cluster did not validate within 15m0s

[2022-08-24T16:07:58.971Z] I0824 16:07:53.703951     321 instancegroups.go:452] Validating the cluster.

[2022-08-24T16:13:36.722Z] I0824 16:13:22.259215     321 instancegroups.go:498] Cluster did not validate, will retry in "30s": unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:13:36.722Z] 	status code: 403, request id: 72e2c489-ec7c-4e80-98dc-cda58e3804ba.

[2022-08-24T16:19:00.195Z] I0824 16:18:57.924309     321 instancegroups.go:498] Cluster did not validate, will retry in "30s": unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:19:00.195Z] 	status code: 403, request id: 62df166c-b6d2-47d0-9967-db488cbe5b76.

[2022-08-24T16:24:54.070Z] I0824 16:24:53.177895     321 instancegroups.go:495] Cluster did not validate within deadline: unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:24:54.070Z] 	status code: 403, request id: abef1974-1752-42e8-82c0-c5cfe6a8b1d2.

[2022-08-24T16:24:54.070Z] E0824 16:24:53.177928     321 instancegroups.go:457] Cluster did not validate within 15m0s

[2022-08-24T16:24:54.070Z] I0824 16:24:53.177945     321 instancegroups.go:452] Validating the cluster.

[2022-08-24T16:32:17.885Z] I0824 16:32:03.178143     321 instancegroups.go:498] Cluster did not validate, will retry in "30s": unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:32:17.885Z] 	status code: 403, request id: ab436289-abec-4c19-8a56-1f68daf6ffe3.

[2022-08-24T16:37:41.710Z] I0824 16:37:40.916761     321 instancegroups.go:498] Cluster did not validate, will retry in "30s": unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:37:41.710Z] 	status code: 403, request id: 4068577b-0255-4bf8-a3fc-d6289d2db07e.

[2022-08-24T16:44:04.955Z] I0824 16:43:57.587224     321 instancegroups.go:495] Cluster did not validate within deadline: unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:44:04.955Z] 	status code: 403, request id: 6d00c28e-f560-4923-985e-c89e0ee45cbc.

[2022-08-24T16:44:04.955Z] E0824 16:43:57.587257     321 instancegroups.go:457] Cluster did not validate within 15m0s

[2022-08-24T16:44:04.955Z] I0824 16:43:57.587273     321 instancegroups.go:452] Validating the cluster.

[2022-08-24T16:49:30.646Z] I0824 16:49:17.122051     321 instancegroups.go:498] Cluster did not validate, will retry in "30s": unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:49:30.646Z] 	status code: 403, request id: 71f5d700-f207-4a77-a16d-5d66d4639967.

[2022-08-24T16:55:39.198Z] I0824 16:55:28.310586     321 instancegroups.go:498] Cluster did not validate, will retry in "30s": unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T16:55:39.198Z] 	status code: 403, request id: d47edcf4-60a9-4058-b003-93e75d567763.

[2022-08-24T17:02:48.991Z] I0824 17:02:40.994726     321 instancegroups.go:495] Cluster did not validate within deadline: unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T17:02:48.991Z] 	status code: 403, request id: 66c94c79-b5df-4fa6-9487-b36c722b3e64.

[2022-08-24T17:02:48.991Z] E0824 17:02:40.994764     321 instancegroups.go:457] Cluster did not validate within 15m0s

[2022-08-24T17:02:48.991Z] I0824 17:02:40.994780     321 instancegroups.go:452] Validating the cluster.

[2022-08-24T17:08:42.381Z] I0824 17:08:29.814311     321 instancegroups.go:498] Cluster did not validate, will retry in "30s": unable to find autoscale groups: error listing autoscaling cluster tags: ExpiredToken: The security token included in the request is expired

[2022-08-24T17:08:42.381Z] 	status code: 403, request id: 53a4ac96-10fc-4a45-969d-df6e77149d39.
```
</details>

What is happening is that each instance group (on some clusters we have quite a few of those) needs to fail before the validation command can completely exit: https://github.com/kubernetes/kops/blob/v1.20.3/pkg/instancegroups/rollingupdate.go#L175-L181

So (assuming we roll an entire cluster at once), if our validation timeout is 15 minutes, and we have X instancegroups, we can expect to take 15 minutes * X amount of time to fail the command. At a minimum, with 3 masters and 1 instancegroup for nodes this ends up being an hour. Some of our clusters have 5 masters and 6 instancegroups, so we end up waiting close to 3 hours for a failure.

**6. What did you expect to happen?**

I expected that kops would fail out early when an instancegroup could not be rolled. That way, the rolling update can only fail for as long as the validation timeout (a maximum of 15 minutes instead of hours).

**7. Please provide your cluster manifest. Execute
  `kops get --name my.example.com -o yaml` to display your cluster manifest.
  You may want to remove your cluster name and other sensitive information.**

Happy to provide, but I don't think this is actually relevant.

**8. Please run the commands with most verbose logging by adding the `-v 10` flag.
  Paste the logs into this report, or in a gist and provide the gist link here.**

Please see the logs above!

**9. Anything else do we need to know?**

Happy to PR this and have the change hidden behind a flag so that existing behavior is not changed.
