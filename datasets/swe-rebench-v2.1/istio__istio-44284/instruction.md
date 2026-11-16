Large HTTPDirectResponse breaks gateways
### Bug Description

Much like #42510 , a large `HTTPDirectResponse` bigger than 4096 bytes breaks gateways.  This results in an error like

```
warn	ads	ADS:RDS: ACK ERROR istio-ingressgateway-internal-844db46d-4vjlr.istio-ingressgateway-internal-4695 Internal:response body size is 15747 bytes; maximum is 4096
```



### Version

```prose
istioctl version
client version: 1.17.2
control plane version: 1.17.2
data plane version: 1.13.3 (1 proxies), 1.16.2 (42 proxies), 1.17.1 (92 proxies), 1.17.2 (45 proxies)

istioctl version --short=false | grep istio-ingressgateway-internal
data plane version: version.ProxyInfo{ID:"istio-ingressgateway-internal-844db46d-4vjlr.istio-ingressgateway-internal", IstioVersion:"1.17.2"}
data plane version: version.ProxyInfo{ID:"istio-ingressgateway-internal-844db46d-krfs8.istio-ingressgateway-internal", IstioVersion:"1.17.2"}
data plane version: version.ProxyInfo{ID:"istio-ingressgateway-internal-844db46d-ql9dr.istio-ingressgateway-internal", IstioVersion:"1.17.2"}

kubectl version
kubectl version --short.  Use --output=yaml|json to get the full version.
Client Version: version.Info{Major:"1", Minor:"25", GitVersion:"v1.25.2", GitCommit:"5835544ca568b757a8ecae5c153f317e5736700e", GitTreeState:"clean", BuildDate:"2022-09-21T14:33:49Z", GoVersion:"go1.19.1", Compiler:"gc", Platform:"darwin/amd64"}
Kustomize Version: v4.5.7
Server Version: version.Info{Major:"1", Minor:"24", GitVersion:"v1.24.9", GitCommit:"57fbbcc2804848b95cad5519f5ec9d6355430db9", GitTreeState:"clean", BuildDate:"2023-02-08T17:22:38Z", GoVersion:"go1.18.9", Compiler:"gc", Platform:"linux/amd64"}
```


### Additional Information

_No response_

### Affected product area

- [ ] Ambient
- [ ] Docs
- [ ] Installation
- [X] Networking
- [ ] Performance and Scalability
- [ ] Extensions and Telemetry
- [ ] Security
- [ ] Test and Release
- [ ] User Experience
- [ ] Developer Infrastructure
- [ ] Upgrade
- [ ] Multi Cluster
- [ ] Virtual Machine
- [ ] Control Plane Revisions

### Additional contract requirements

- The Envoy `RouteConfiguration` generated for gateway and sidecar outbound HTTP traffic must set its `MaxDirectResponseBodySizeBytes` field to 1024 * 1024 bytes (1 MiB), raising Envoy's default of 4096 bytes so that large direct responses are accepted.
