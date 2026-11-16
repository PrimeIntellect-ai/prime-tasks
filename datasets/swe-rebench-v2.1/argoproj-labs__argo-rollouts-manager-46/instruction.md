reflect.DeepEqual does not work well when comparing expected Rollouts Deployment resource and live Rollouts Deployment resource
We have logic in `deployment.go` which attempts to compare the expected (target) contents of the Argo Rollouts `Deployment` resource with the live on-cluster contents of that resource, and iff they differ it will update the live copy.

However, at present, that logic will *always* cause an Update, because `reflect.DeepEqual()` is matching fields with default values that are set in the live object, but not set in the expected object.
