Unable to set Loadbalancer Service Health Probe Port
Reopen from #1499

When configuring Health Checks for Azure Load Balancer you can specify the path and type, but it is not possible to specify the port of the health probe.

Istio Ingress Gateway and similar services do not expose health checks on their actual endpoints (as it can operate across multiple protocols) but instead expose a general health check on a different status port for the gateway.

In AWS this is easily possible with the service.beta.kubernetes.io/aws-load-balancer-healthcheck-port annotation but it does not seem possible in Azure.

This prevents us from configuring health check probes against Istio which need to be targeting the "Status Ready" port not the actual port of the backend.

## Example

Istio hosted on two ports: Port 80 and Port 443 will not serve any traffic until a Virtual Service is deployed
The health check needs to be a HTTP health check against the status port, let's say that's 15021
The probe protocol and endpoint and everything can be set, but the health check port cannot be.

For the following spec:
```
spec:
  ports:
    - name: http2
      protocol: TCP
      port: 80
      targetPort: 8080
    - name: https
      protocol: TCP
      port: 443
      targetPort: 8443
```

The generated probe needs to look like this:

![image](https://user-images.githubusercontent.com/2106153/163554395-cbe76f4b-fa39-4ea8-862f-c889db695f38.png)

### Additional contract requirements

The health probe port for a LoadBalancer Service is configured per service port with the
annotation key `service.beta.kubernetes.io/port_{port}_health-probe_port`, where `{port}` is
the numeric service port (for example `service.beta.kubernetes.io/port_80_health-probe_port`).
The annotation value is the port number that the generated health probe targets, overriding
the default probe port (the service port's nodePort). The probe keeps being named after the
service port it is associated with.
