Add Server Name to Leafz Monitoring Endpoint
## Feature Request
In the monitoring endpoint, for /Leafz, add serverName attribute of the Leafnode that connected.

#### Use Case:
The IP doesn't give us all of the information that we need to uniquely identify which of the many Leafnodes that are connecting to the core nats server. For example, we have connections coming outside of our network that get DNAT to a different IP that the original leafnode server was using. Also, deploying within a K8S environment uses the internal K8S IP and tracking it down can be difficult.

#### Proposed Change:
[HIDDEN]

#### Who Benefits From The Change(s)?
Anyone that uses K8S or bridges networks together where DNAT is involved.

#### Alternative Approaches
Build out a better way of showing the entire nats / leafnodes topology.

### Additional contract requirements

Each leaf entry in the `/leafz` JSON response must expose the connected leaf node’s configured server name as a string in the `name` property.
