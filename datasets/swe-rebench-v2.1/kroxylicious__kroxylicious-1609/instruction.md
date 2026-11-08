Broker address used by proxy uses relative DNS name
**Describe the bug**

I've been experimenting with the proxy.

The broker address used by the proxy assumes the client will run within the same namespace as the proxy. In other words, it uses a relative DNS rather than an absolute one.

```
kubectl -n my-proxy run node-list -ti --image=quay.io/kroxylicious/kaf --rm=true --restart=Never -- kaf node ls -b my-cluster.my-proxy.svc.cluster.local:9292
ID    ADDRESS           CONTROLLER
0     my-cluster:9293   true
```


**To Reproduce**
Steps to reproduce the behavior:
1. Deploy the proxy operator as per kroxylicious-operator/DEV_GUIDE.md
2. Use Strimzi [quickstart](https://strimzi.io/quickstarts/) to deploy Strimzi operator and create `kafka-single-node`.
3. Create a proxy using the following:
```yaml
metadata:
  name: simple
  namespace: my-proxy
spec:
  clusters:
  - name: my-cluster
    upstream:
      bootstrapServers: my-cluster-kafka-bootstrap.kafka.svc:9092
```
4. Create a topic running the client in the same namespace as the proxy (works)
```
kubectl -n my-proxy run node-list -ti --image=quay.io/kroxylicious/kaf --rm=true --restart=Never -- kaf topic create  -b my-cluster.my-proxy.svc.cluster.local:9292  foo
```
5. Create a topic running the client in the different namespace as the proxy (**fails**)
```
kubectl -n kafka run node-list -ti --image=quay.io/kroxylicious/kaf --rm=true --restart=Never -- kaf topic create  -b my-cluster.my-proxy.svc.cluster.local:9292  bar
Could not create topic bar: dial tcp: lookup my-cluster on 10.96.0.10:53: no such host

pod "node-list" deleted
pod kafka/node-list terminated (Error)
```
**Expected behavior**

I should be able to run the client anywhere on the cluster (assuming sufficient RBAC of course).

**YAML files and logs**

Attach or copy paste your kroxylicious configuration YAML (with sensitive details
like broker address redacted).
Attach or copy and paste relevant logs.

**Additional context**
Add any other context about the problem here.


[HIDDEN]

### Additional contract requirements

Broker addresses advertised by the proxy must use a fully qualified service hostname so that clients in any namespace in the cluster can resolve and connect to the broker through the proxy.
