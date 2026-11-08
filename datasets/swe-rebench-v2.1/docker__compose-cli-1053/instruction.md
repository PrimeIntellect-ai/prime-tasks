ACI: 'run' command fails to create UDP protocol binding for public IP address
**Steps to reproduce the issue:**
1. Create ACI Docker context e.g. 'acictx'
2. `docker --context acictx run -d -p 12345/udp some-udp-based-network-service-image`

**Describe the results you received:**
No errors/warnings, but the public IP address created as part of the ACI container group is using TCP protocol

**Describe the results you expected:**
The public IP address created as part of the ACI container group should use UDP protocol

**Additional information you deem important (e.g. issue happens only occasionally):**
You can verify the protocol used by the IP address with Azure CLI (`az container show`). Deploying via `az container create` works as expected (UDP protocol binding is created and communication works).

Tried on Docker Desktop for Mac 2.5.2 (50156). Also tried on Ubuntu Linux with the same effect.

### Additional contract requirements

- When a service's published ports are converted to ACI port definitions, each port's protocol must be derived from the service port configuration: an empty protocol or `tcp` maps to TCP, and `udp` maps to UDP. This applies both to the container-level port definitions and to the group-level (public IP address) port definitions.
- A published port whose published value differs from its target (a host-to-container port mapping) must be rejected with a non-nil error.
- A port whose protocol is neither empty, `tcp`, nor `udp` must be rejected with a non-nil error.
