Tunneling agent IP should not be reported as cluster's status.address.ip
When Tunneling expose trategy is used, the "special" (private) tunneling agent IP is reported into cluster's `status.address.ip` ([code pointer](https://github.com/kubermatic/kubermatic/blob/10e2d62449faec9fadd89c14f9501df89b4e4b2e/pkg/resources/address/address.go#L169)).

This is not correct, as it should contain cluster's external IP address. This can break e.g. web terminal which relies on this IP in its network policy (even though its network policy should probably also support list of multiple IPs, such as [here](https://github.com/kubermatic/kubermatic/blob/10e2d62449faec9fadd89c14f9501df89b4e4b2e/pkg/controller/seed-controller-manager/kubernetes/resources.go#L623-L629)).
