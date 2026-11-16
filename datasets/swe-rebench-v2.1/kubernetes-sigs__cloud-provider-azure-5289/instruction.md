Multiple Standard LoadBalancers doesn't respect ServiceLabelSelector
#### What happened:

Having the below SLB config to distribute Service creation between 3 Azure Load Balancers:
```json
"multipleStandardLoadBalancerConfigurations": [
  {
    "name": "kubernetes",
    "primaryVMSet": "sys"
  },
  {
    "name": "nginx1",
    "primaryVMSet": "nginx1"
    "ServiceLabelSelector": {
      "matchLabels": {
        "app.kubernetes.io/name": "nginx"
      }
    }
  },
  {
    "name": "nginx2",
    "primaryVMSet": "nginx2"
    "ServiceLabelSelector": {
      "matchLabels": {
        "app.kubernetes.io/name": "nginx"
      }
    }
  },
  {
    "name": "nginx3",
    "primaryVMSet": "nginx3"
    "ServiceLabelSelector": {
      "matchLabels": {
        "app.kubernetes.io/name": "nginx"
      }
    }
  }
]
```

And creating a `Service` with label `app.kubernetes.io/name: ingress-nginx` makes all 4 SLB configs eligable for placement.

#### What you expected to happen:

Only the SLB configs matching the `ServiceLabelSelector` should be eligable.

#### How to reproduce it (as minimally and precisely as possible):

1. Run `cloud-controller-manager` with `--v=10` or higher (or attach to debugger)
2 .Appy the following manifests

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: nginx
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: nginx
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        env:
        - name: NGINX_PORT
          value: "8080"
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
      nodeSelector:
        kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: nginx1
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "false"
  labels:
    app.kubernetes.io/name: nginx
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: nginx
  ports:
  - port: 80
    targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: nginx2
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "false"
  labels:
    app.kubernetes.io/name: nginx
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: nginx
  ports:
  - port: 80
    targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: nginx3
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "false"
  labels:
    app.kubernetes.io/name: nginx
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: nginx
  ports:
  - port: 80
    targetPort: http
```

3. Notice that the `kubernetes` SLB is eligable for placement

#### Anything else we need to know?:

Issue tested on version 1.28.4.

The issue lays in how eligability based on selectors are implemented. Currently they only remove SLB's with selectors from the list when that's the case. And in the case of having a service with a label or namespace selector it always returns the complete list of SLB's.

The expected behaviour is that if there's a label match, only the matches SLB's are eligable.

#### Environment:

- Kubernetes version (use `kubectl version`): 1.26.11
- Cloud provider or hardware configuration: Self-managed Kubernetes on Azure with CAPZ
- OS (e.g: `cat /etc/os-release`): Ubuntu 22.04.3 LTS
- Kernel (e.g. `uname -a`): 6.2.0-1017-azure 17~22.04.1-Ubuntu SMP
- Install tools: CAPZ
- Network plugin and version (if this is a network-related bug): N/A
- Others: N/A
