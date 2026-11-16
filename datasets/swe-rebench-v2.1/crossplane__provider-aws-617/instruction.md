ec2.sg: panic when sorting ingress/egress rules without port (ipProtocol -1)
### What happened?
panic when sorting ingress/egress rules
```
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws panic: runtime error: invalid memory address or nil pointer dereference [recovered]
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws 	panic: runtime error: invalid memory address or nil pointer dereference
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws [signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x1dc6042]
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws goroutine 1589 [running]:
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws k8s.io/apimachinery/pkg/util/runtime.HandleCrash(0x0, 0x0, 0x0)
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws 	/home/.../src/provider-aws/.work/pkg/pkg/mod/k8s.io/apimachinery@v0.20.1/pkg/util/runtime/runtime.go:55 +0x109
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws panic(0x272c760, 0x47ec060)
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws 	/home/.../opt/go/src/runtime/panic.go:965 +0x1b9
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws github.com/crossplane/provider-aws/pkg/clients/ec2.CreateSGPatch.func1(0x6, 0x0, 0x2646d60)
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws 	/home/.../src/provider-aws/pkg/clients/ec2/securitygroup.go:308 +0x42
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws sort.quickSort_func(0xc0017d89f0, 0xc00123f950, 0x0, 0x8, 0x8)
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws 	/home/.../opt/go/src/sort/zfuncversion.go:154 +0x1b8
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws sort.Slice(0x2554260, 0xc001c2a228, 0xc0017d89f0)
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws 	/home/.../opt/go/src/sort/slice.go:20 +0xe8
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws github.com/crossplane/provider-aws/pkg/clients/ec2.CreateSGPatch(0xc0011b4e40, 0xc0011b4e70, 0xc0011b4ea0, 0xc001173980, 0x1, 0x1, 0xc0008e4e00, 0x7, 0x7, 0xc0011b55d0, ...)
crossplane-provider-aws-c2ea9b021877-7795f8c8d9-c72tw provider-aws 	/home/.../src/provider-aws/pkg/clients/ec2/securitygroup.go:307 +0x50d
```


### How can we reproduce it?
```
apiVersion: ec2.aws.crossplane.io/v1beta1
kind: SecurityGroup
metadata:
  name: test
spec:
  forProvider:
    description: test
    groupName: test
    ingress:
    - ipProtocol: "-1"
      ipRanges:
      - cidrIp: 10.0.1.0/24
    - ipProtocol: "-1"
      ipRanges:
      - cidrIp: 10.0.4.0/24
    region: eu-north-1
    vpcId: ...
  providerConfigRef:
    name: default
```

### What environment did it happen in?
Crossplane version: 0.17

<!--
Include at least the version or commit of Crossplane you were running. Consider
also including your:

* Cloud provider or hardware configuration
* Kubernetes version (use `kubectl version`)
* Kubernetes distribution (e.g. Tectonic, GKE, OpenShift)
* OS (e.g. from /etc/os-release)
* Kernel (e.g. `uname -a`)
-->
