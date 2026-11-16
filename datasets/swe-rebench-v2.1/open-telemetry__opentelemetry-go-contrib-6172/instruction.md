[otelmongo] bump semconv to 1.26.0
### Problem Statement

otelmongo is currently using [semconv/v1.17.0](https://github.com/open-telemetry/opentelemetry-go/pull/3599), suggest updating to [semconv/v1.26.0](https://github.com/open-telemetry/opentelemetry-go/pull/5476).

### Proposed Solution
key/value pair changes migrating from 1.17.0 to 1.26.0 include:

<table>
  <tr>
   <td><strong>Old Func</strong>
   </td>
   <td><strong>New Func</strong>
   </td>
   <td><strong>Old Key</strong>
   </td>
   <td><strong>New Key</strong>
   </td>
   <td><strong>Notes</strong>
   </td>
  </tr>
  <tr>
   <td><code>DBOperation</code>
   </td>
   <td><code>DBOperationName</code>
   </td>
   <td><code>db.operation</code>
   </td>
   <td><code>db.operation.name</code>
   </td>
   <td>
   </td>
  </tr>
  <tr>
   <td><code>DBName</code>
   </td>
   <td><code>DBNamespace</code>
   </td>
   <td><code>db.name</code>
   </td>
   <td><code>db.namespace</code>
   </td>
   <td>
   </td>
  </tr>
  <tr>
   <td><code>NetPeerName</code>
   </td>
   <td><code>NetworkPeerAddress</code>
   </td>
   <td><code>net.peer.name</code>
   </td>
   <td><code>network.peer.address</code>
   </td>
   <td>Currently the hostname is used for the peer name. Documentation suggest using the server address.
   </td>
  </tr>
  <tr>
   <td><code>NetPeerPort</code>
   </td>
   <td><code>NetworkPeerPort</code>
   </td>
   <td><code>net.peer.port</code>
   </td>
   <td><code>network.peer.port</code>
   </td>
   <td>
   </td>
  </tr>
  <tr>
   <td><code>NetTransportTCP</code>
   </td>
   <td><code>NetworkingTransportTCP</code>
   </td>
   <td><code>net.transport</code>
   </td>
   <td><code>network.transport</code>
   </td>
   <td>Network transport no longer includes the <code>ip_</code> portion defined on the deprecated <code>net.trasnport</code>. Instead, this value is either <code>tcp</code> or <code>udp</code>.
   </td>
  </tr>
  <tr>
   <td><code>DBStatement</code>
   </td>
   <td><code>DBQueryText</code>
   </td>
   <td><code>db.statement</code>
   </td>
   <td><code>db.query.text</code>
   </td>
   <td>There is no deprecated analogue to `db.statement` according to the documentation. <code>Db.query.text</code> seemed like a natural fit.
   </td>
  </tr>
</table>


#### Alternatives

Since these fields are deprecated, there is no alternative other than leaving the semconv version static.

#### Prior Art

NA

### Additional Context

It's worth noting that this is a breaking change if telemetry key/values are considered stable.

### Additional contract requirements

- For v1.26.0, the `network.peer.address` attribute must contain the server host and port in `host:port` form (for example, `host:1`).
