DefaultDomain should be the cluster's domain and not hardcoded to `svc.cluster.local`
Rather than hardcode the default domain I think we should use the cluster's domain from the knative/pkg helper

https://github.com/knative/serving/blob/ea2a6c8c6166d27b3251469400efed33125cac15/pkg/reconciler/route/config/domain.go#L34-L36

and use
```go
network.GetClusterDomainName()
```

https://github.com/knative/pkg/blob/db8a35330281c41c7e8e90df6059c23a36af0643/network/domain.go#L46

I don't think we catch this in our e2e tests because we use a fake domain name - https://github.com/knative/serving/blob/ea2a6c8c6166d27b3251469400efed33125cac15/test/config/ytt/core/overlay-config-domain.yaml

FYI @psschwei @nak3
