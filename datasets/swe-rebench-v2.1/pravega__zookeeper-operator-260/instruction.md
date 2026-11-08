annotations does not take effect
```
apiVersion: zookeeper.pravega.io/v1beta1
kind: ZookeeperCluster
metadata:
  name: zookeepercluster
spec:
  # Add fields here
  replicas: 3
  pod:
    # 发现注解字段不生效
    annotations:
      sidecar.istio.io/inject: "false"


when i check pod:
kubectl get pod zookeepercluster-0 -o yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    sidecar.istio.io/status: '{"version":"761ebc5a63976754715f22fcf548f05270fb4b8db07324894aebdb31fa81d960","initContainers":null,"containers":["istio-proxy"],"volumes":["istio-envoy","istio-certs"],"imagePullSecrets":null}'
    tke.cloud.tencent.com/networks-status: |-
      [{
          "name": "tke-bridge",
          "ips": [
              "172.31.11.142"
          ],
          "default": true,
          "dns": {}
      }]


when i check statefulsets:
kubectl get statefulsets.apps  zookeepercluster  -o yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  creationTimestamp: "2020-02-12T11:40:33Z"
  generation: 1
  labels:
    app: zookeepercluster
    release: zookeepercluster
  name: zookeepercluster
  namespace: default
  ownerReferences:
  - apiVersion: zookeeper.pravega.io/v1beta1
    blockOwnerDeletion: true
    controller: true
    kind: ZookeeperCluster
    name: zookeepercluster
    uid: 7acda871-4d8c-11ea-a8df-525400fe84b0
  resourceVersion: "49757594"
  selfLink: /apis/apps/v1/namespaces/default/statefulsets/zookeepercluster
  uid: 7ad28a02-4d8c-11ea-b662-525400122c98
```

I can not find annotations with sidecar.istio.io/inject: false
