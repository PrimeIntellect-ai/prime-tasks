Deployment fail in specific case
Noticed failed deployment in following scenario:

application with CronJob only resource which triggers Job every hour. argo-watcher committed override, argocd synced it, but previous job configuration with old image. Unless new Job is triggered, the deployment's validation fails.

### Additional contract requirements

For deployments where a scheduled workload such as a CronJob may not create a new Job immediately, operators must be able to opt in to completing the deployment without waiting for the new image to appear in a newly created Job. Set the application annotation `argo-watcher/fire-and-forget` to the string value `"true"` to enable this behavior. With this annotation enabled, the rollout is considered deployed despite the stale image in the prior Job.
