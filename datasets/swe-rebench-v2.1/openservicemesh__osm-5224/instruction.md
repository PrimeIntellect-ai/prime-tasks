Make app protocol detection of service port less error prone
**Please describe the Improvement and/or Feature Request**
Currently, OSM implicitly uses http as the app protocol for a k8s service port if it can't derive the port's protocol using the `appProtocol` field or from the port's name.
https://github.com/openservicemesh/osm/blob/ee7e846a2ff0005f962e8bd867944c3f2a46b6f7/pkg/compute/kube/client.go#L511-L525

It's possible for a k8s service to use the same port for multiple protocols, e.g. port 53 for DNS can be TCP or UDP. When a port's protocol is unset based on the [app protocol selection behavior](https://release-v1-2.docs.openservicemesh.io/docs/guides/app_onboarding/app_protocol_selection/), the configuration can result in duplicate Envoy filter_chain_match configuration. This happens because OSM implicitly sets the appProtocol to `http` for unknown port protocols. So a configuration such as the below can result in duplicate filter_match_configuration:
```
ports:
  - name: myPort
    port: 8080
    protocol: udp
  - name: myPort2
    port: 8080
    protocol: tcp
    appProtocol: http
```

> Note: the protocol is implicitly set to http when it's unspecified for backward compatibility reasons. We do not want to break existing users relying on this behavior, as http apps are more common. In the future, we can consider making the protocol specification explicit at all times.

This issue proposes to do the following:
1. When `port.protocol` is UDP, to not set MeshService.Protocol to `http`, but to leave it as is and let it result in an error log when the code that builds the config sees an unsupported protocol
2. Add a warn log when MeshService.Protocol is implicitly set to `http`. This log will be useful to identify scenarios where there is a protocol related error with traffic.
