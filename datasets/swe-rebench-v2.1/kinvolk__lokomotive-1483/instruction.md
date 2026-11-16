Rook: Ceph OSDs consume up to 12 GB memory
tl;dr: Provide a way for the user where they can limit the memory and CPU of the ceph sub-components like OSD, MGR, MON, etc.

---

Right now there is no way for a user to specify memory limits on the OSD or any other sub-components of Rook. Since there are no resource limits specified the pod uses all the memory availble on the host.

As you can see that the following OSD deployment has no Kubernetes resources (memory or cpu and limits or request) set. But still the env vars are trying to reference them. So here empty values are being referenced:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
  name: rook-ceph-osd-28
  namespace: rook
...
      containers:
      - args:
        - --foreground
        - --id
        - "28"
        - --fsid
        - 77d48d93-351e-4a00-a554-d99e625914d7
        - --setuser
        - ceph
        - --setgroup
        - ceph
        - --crush-location=root=default host=lokomotive-production-storage-worker-2
          region=ewr1
        - --log-to-stderr=true
        - --err-to-stderr=true
        - --mon-cluster-log-to-stderr=true
        - '--log-stderr-prefix=debug '
        - --default-log-to-file=false
        - --default-mon-cluster-log-to-file=false
        - --ms-learn-addr-from-peer=false
        command:
        - ceph-osd
        env:
        - name: POD_MEMORY_LIMIT
          valueFrom:
            resourceFieldRef:
              divisor: "0"
              resource: limits.memory
        - name: POD_MEMORY_REQUEST
          valueFrom:
            resourceFieldRef:
              divisor: "0"
              resource: requests.memory
        - name: POD_CPU_LIMIT
          valueFrom:
            resourceFieldRef:
              divisor: "1"
              resource: limits.cpu
        - name: POD_CPU_REQUEST
          valueFrom:
            resourceFieldRef:
              divisor: "0"
              resource: requests.cpu
        image: ceph/ceph:v15.2.5-20200916
        name: osd
        resources: {}
```

One would expect that empty values are populated inside the pod, but if you see the env vars all the limit values are capped at the host limits:

```bash
POD_MEMORY_LIMIT=135039045632
POD_MEMORY_REQUEST=0
POD_CPU_LIMIT=32
POD_CPU_REQUEST=0
```

This host has 125 GB memory and 32 cores of CPU.

Above automatically reflects in the OSD config:

```
[root@rook-ceph-tools-6f7fccd4d6-fvgbk /]# ceph tell osd.28 config show | grep memory
    "osd_memory_base": "805306368",
    "osd_memory_cache_min": "134217728",
    "osd_memory_cache_resize_interval": "1.000000",
    "osd_memory_expected_fragmentation": "0.150000",
    "osd_memory_target": "108031236505",
    "osd_memory_target_cgroup_limit_ratio": "0.800000",
```

`osd_memory_target` is the amount of memory that OSD is allowed to expand upto. And it is appropriately set proportional to the host memory limit.

```
osd_memory_target = floor( POD_MEMORY_LIMIT * osd_memory_target_cgroup_limit_ratio )
```

### Additional contract requirements

- Expose these settings through HCL blocks under `resources`: `osd`, `mgr`, `mon`, `mds`, `prepareosd`, `crashcollector`, and `mgr_sidecar`. Each component block may contain `requests` and/or `limits` blocks with `cpu` and `memory` string values. Render the supplied settings under `.spec.resources` in the CephCluster manifest, using `mgr-sidecar` as the output key for `mgr_sidecar`. Include only the supplied request, limit, CPU, and memory fields.
