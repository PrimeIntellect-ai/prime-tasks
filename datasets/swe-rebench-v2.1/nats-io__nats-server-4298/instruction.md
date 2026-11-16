Client connections load balancing among nats cluster nodes
Hello! Currently the mechanism of load balancing of client connections to nats cluster is based on random node selection. The problem (already discussed in some of the issues, like https://github.com/nats-io/nats-server/issues/1359) is when we restart nats cluster. To be able to serve clients we restart cluster one node after another and this will lead us to approximately the following distribution (step-by-step example for 3 node cluster):
1) original connection distribution is 24 / 24 / 24
2) after node1 restart : 0 / 36 / 36
3) after node2 restart:  18 / 0 / 54
4) after node3 restart: 45 / 27 / 0

As you can see original uniform distribution 1/3 | 1/3 | 1/3 tends to 2/3 | 1/3 | 0 . I suggest you to add some modifications that will allow developers to get around this problem (for example, we use nats cluster in 24/7 fashion and never stop it completely but sometimes need to upgrade server version or our hardware). There can be several solutions:
1) Implement clever load balancing (when nats cluster node tells client to try to connect to another known node which have less active clients)
2) Provide a command which can be sent to cluster and cause it to disconnect existing clients - we can use it after cluster restart is finished to redistribute client connections among nodes.

### Additional contract requirements

- An operator must be able to disconnect an existing client connection on a specific server so that the client reconnects and can land on another node. This is requested through a system request sent to `$SYS.REQ.SERVER.<server id>.KICK`, where `<server id>` is the ID of the server holding the connection.
- The request payload is a JSON object with a `cid` field holding the connection ID of the client, as returned by the client library's `GetClientID`.
- After the request succeeds, the targeted client connection is closed by the server and the client observes a disconnection.
