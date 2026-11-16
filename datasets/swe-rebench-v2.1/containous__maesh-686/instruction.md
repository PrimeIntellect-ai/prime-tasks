Maesh Corefile patch: upstream causing coredns to crash
<!-- PLEASE FOLLOW THE ISSUE TEMPLATE TO HELP TRIAGE AND SUPPORT! -->

## Bug Report

`upstream` in CoreDNS Corefile is causing it to end in a crash loop with the following error:

```
Error during parsing: unknown property 'upstream'
```

### What did you do?

Installed Maesh v1.3.2 with the official Helm chart.

<!--
HOW TO WRITE A GOOD BUG REPORT?

- Respect the issue template as much as possible.
- The title should be short and descriptive.
- Explain the conditions which led you to report this issue: the context.
- The context should lead to something, an idea or a problem that you’re facing.
- Remain clear and concise.
- Format your messages to help the reader focus on what matters and understand the structure of your message, use Markdown syntax https://help.github.com/articles/github-flavored-markdown
-->

### What did you expect to see?

CoreDNS pod functioning.

### What did you see instead?

CoreDNS pod in a crash loop, outputting the following logs:

```
$ kubectl logs deploy/coredns -n kube-system
plugin/kubernetes: /etc/coredns/Corefile:25 - Error during parsing: unknown property 'upstream'
```

But when I edit the `coredns` ConfigMap and remove `upstream`, the `coredns` pod runs appropriately.

### Output of controller log: (_What version of Maesh are you using?_)

<!---
`latest` is not considered as a valid version.
We need a release number!
-->

```
v1.3.2
```

### What is your environment & configuration (arguments, provider, platform, ...)?

N/A

### If applicable, please paste the yaml objects required to reproduce your issue

```
kind: ConfigMap
apiVersion: v1
metadata:
  name: coredns
  namespace: kube-system
  selfLink: /api/v1/namespaces/kube-system/configmaps/coredns
  uid: 0abbbf22-0f79-424e-a22c-e7eabf6d9465
  resourceVersion: '2842406969'
  creationTimestamp: '2020-06-10T11:24:47Z'
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
    k8s.scw.cloud/object: ConfigMap
    k8s.scw.cloud/system: coredns
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: >
      {"apiVersion":"v1","data":{"Corefile":".:53 {\n    errors\n    health\n
      kubernetes cluster.local in-addr.arpa ip6.arpa {\n        pods
      insecure\n        fallthrough in-addr.arpa ip6.arpa\n    }\n    prometheus
      :9153\n    forward . /etc/resolv.conf\n    cache 30\n    loop\n
      reload\n
      loadbalance\n}\n"},"kind":"ConfigMap","metadata":{"annotations":{},"labels":{"addonmanager.kubernetes.io/mode":"EnsureExists","k8s.scw.cloud/object":"ConfigMap","k8s.scw.cloud/system":"coredns"},"name":"coredns","namespace":"kube-system"}}
  managedFields:
    - manager: kubectl
      operation: Update
      apiVersion: v1
      time: '2020-07-22T11:51:06Z'
      fieldsType: FieldsV1
      fieldsV1:error
        'f:data': {}
        'f:metadata':
          'f:annotations':
            .: {}
            'f:kubectl.kubernetes.io/last-applied-configuration': {}
          'f:labels':
            .: {}
            'f:addonmanager.kubernetes.io/mode': {}
            'f:k8s.scw.cloud/object': {}
            'f:k8s.scw.cloud/system': {}
    - manager: maesh
      operation: Update
      apiVersion: v1
      time: '2020-07-22T15:51:12Z'
      fieldsType: FieldsV1
      fieldsV1:
        'f:data':
          'f:Corefile': {}
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }

    #### Begin Maesh Block
    maesh:53 {
        errors
        rewrite continue {
            name regex ([a-zA-Z0-9-_]*)\.([a-zv0-9-_]*)\.maesh maesh-{1}-6d61657368-{2}.maesh.svc.cluster.local
            answer name maesh-([a-zA-Z0-9-_]*)-6d61657368-([a-zA-Z0-9-_]*)\.maesh\.svc\.cluster\.local {1}.{2}.maesh
        }
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            upstream
            fallthrough in-addr.arpa ip6.arpa
        }
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
    #### End Maesh Block
```

### Additional contract requirements

- The `upstream` directive must be omitted from the Maesh CoreDNS block for CoreDNS versions 1.7 and newer (including 1.7.0). It must be retained for CoreDNS versions older than 1.7.
