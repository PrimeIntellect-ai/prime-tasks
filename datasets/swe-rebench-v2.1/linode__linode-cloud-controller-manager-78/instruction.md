LoadBalancer Services cannot discover the true ClientIP

X-Forwarded-For, X-Real-IP, ProxyProtocol and friends currently see only an IP in the range 192.168.255.0/24

### Additional contract requirements

A Service may use the `service.beta.kubernetes.io/linode-loadbalancer-proxy-protocol` annotation to choose the NodeBalancer ProxyProtocol setting. The supported values are `none`, `v1`, and `v2`; the selected value is reflected in the NodeBalancer configuration, and an unsupported value causes the Service update to fail.
