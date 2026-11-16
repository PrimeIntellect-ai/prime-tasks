KubeVirt csi-controller: fix flaky e2e tests
In the ci, there is only 1 node.

Depending on the reconciliation order, the `csi-controller` deployment that depends on the `csi-infra-kubeconfig ` Secret mounted as Volume is updated with the new Secret version.

If the `csi-controller` is already started, and if the cluster (seed cluster) has only 1 node, then then new `csi-controller` pod will not start with this error:
`Warning  FailedScheduling  30s   default-scheduler  0/1 nodes are available: 1 node(s) didn’t have free ports for the requested pod ports. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.`

This is due to the `csi-driver` container :
```
Ports: []corev1.ContainerPort{
                        {
                            Name:          "healthz",
                            ContainerPort: 10301,
                            [HIDDEN]
                            Protocol:      corev1.ProtocolTCP,
                        },
                    },
```

If the seed cluster has only 1 node, the port is busy with the first `csi-controller` pod and the new pod can not start.

On a seed cluster with several (Ready) nodes, this issue does not occur.
A prod seed cluster would also have several Ready nodes to let the rollout finish and start the new `csi-controller` pod.

However, let solve this, at least for the sake of the `ci` e2e tests.

### Additional contract requirements

- A replacement KubeVirt `csi-controller` pod must be able to start on a one-node seed cluster while the existing `csi-controller` pod is still running. The `csi-controller` pod must not reserve a host port that prevents a second instance from being scheduled on the same node.
