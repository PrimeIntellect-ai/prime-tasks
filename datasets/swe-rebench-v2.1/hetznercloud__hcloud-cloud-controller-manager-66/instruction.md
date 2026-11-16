Not possible to configure the annotation load-balancer.hetzner.cloud/health-check-port
As far as I can tell there is no working way to specify the health-check-port the controller should configure.

* it's not possible to set it as an integer. From what I found only strings are allowed in annotations/labels (https://github.com/kubernetes/kubernetes/issues/57509)
* if it's not an integer the controller doesn't process the annotation

https://github.com/hetznercloud/hcloud-cloud-controller-manager/commit/df90212c1c022a1cb892c19466d6efa38cb925f2#r40335885

### Additional contract requirements

- A health-check-port annotation supplied as a Kubernetes string value must configure that port.
- When the `load-balancer.hetzner.cloud/health-check-port` annotation is set
  but the `load-balancer.hetzner.cloud/health-check-protocol` annotation is
  not, the health check protocol defaults to the service protocol, so the
  requested health check port is configured with a valid protocol.
- Health check settings whose annotations are not set are left unset
  (omitted) so the API applies its own defaults. In particular, when only
  the health-check-port annotation is set, the health check interval,
  timeout and retries are not sent.
