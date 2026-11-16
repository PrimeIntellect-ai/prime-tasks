ApplicationSet Controller Panics when Cluster Secret is malformed
Situation:  We found that the ApplicationSet controller v0.2.0 was in a crash loop back-off in my cluster.  The stack trace (will go looking for that in a moment) indicated an unexpected newline when unmarshaling the data.config, pointing to this line:

https://github.com/argoproj-labs/applicationset/blob/master/pkg/utils/clusterUtils.go#L107

The root cause was that the secret was created and the caBundle field was not base64 encoded.  Removing those secrets and restarting the ApplicationSet controller resolved the issue.

I'm wondering if a panic is an appropriate response, or just eliminate the affected cluster from the current compilation scope.

### Additional contract requirements

A malformed cluster Secret must be handled without panicking the controller. The failure may be propagated as an error that prevents cluster listing, or the malformed cluster may be excluded while other valid clusters remain usable.
