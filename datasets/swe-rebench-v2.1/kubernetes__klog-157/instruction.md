Fix `InfoS` serializing Stringer subfields
/kind bug

**What steps did you take and what happened:**

When migrating `Infof` to `InfoS` there was a regression in serializing Stringer subfields.
```
klog.V(2).Infof("status for pod %v updated to %v", p.Name, status)
```
was correctly migrated to
```
klog.V(2).InfoS("Pod status updated", "pod", klog.KObj(p), "status", status)
```
Log output before migration
```
I0601 19:25:53.698080   16895 kubelet_getters.go:173] status for pod nginx-pod-127.0.0.1 updated to {Running [{Initialized True 0001-01-01 00:00:00 +0000 UTC 2020-06-01 19:18:54 +0900 JST  } {Ready True 0001-01-01 00:00:00 +0000 UTC 2020-06-01 19:18:54 +0900 JST  } {ContainersReady True 0001-01-01 00:00:00 +0000 UTC 2020-06-01 19:18:54 +0900 JST  } {PodScheduled True 0001-01-01 00:00:00 +0000 UTC 2020-06-01 19:18:54 +0900 JST  }]    127.0.0.1 172.17.0.4 [{172.17.0.4}] 2020-06-01 19:18:54 +0900 JST [] [{nginx-container {nil &ContainerStateRunning{StartedAt:2020-06-01 18:27:34 +0900 JST,} nil} {nil nil nil} true 0 nginx:latest docker-pullable://nginx@sha256:6fff55753e3b34e36e24e37039ee9eae1fe38a6420d8ae16ef37c92d1eb26699 docker://c729caca14fd6b19fb1fdbf5fe436352abd31c488a134fd5e56ee9fe7dc98eaa 0xc0012c2069}] BestEffort []}
```
log output after migration
```
I0601 19:45:29.666416   27921 kubelet_getters.go:173] "Pod status updated" pod="default/nginx-pod-127.0.0.1" status=v1.PodStatus{Phase:"Running", Conditions:[]v1.PodCondition{v1.PodCondition{Type:"Initialized", Status:"True", LastProbeTime:v1.Time{Time:time.Time{wall:0x0, ext:0, loc:(*time.Location)(nil)}}, LastTransitionTime:v1.Time{Time:time.Time{wall:0x0, ext:63726604110, loc:(*time.Location)(0x750f720)}}, Reason:"", Message:""}, v1.PodCondition{Type:"Ready", Status:"True", LastProbeTime:v1.Time{Time:time.Time{wall:0x0, ext:0, loc:(*time.Location)(nil)}}, LastTransitionTime:v1.Time{Time:time.Time{wall:0x0, ext:63726604110, loc:(*time.Location)(0x750f720)}}, Reason:"", Message:""}, v1.PodCondition{Type:"ContainersReady", Status:"True", LastProbeTime:v1.Time{Time:time.Time{wall:0x0, ext:0, loc:(*time.Location)(nil)}}, LastTransitionTime:v1.Time{Time:time.Time{wall:0x0, ext:63726604110, loc:(*time.Location)(0x750f720)}}, Reason:"", Message:""}, v1.PodCondition{Type:"PodScheduled", Status:"True", LastProbeTime:v1.Time{Time:time.Time{wall:0x0, ext:0, loc:(*time.Location)(nil)}}, LastTransitionTime:v1.Time{Time:time.Time{wall:0x0, ext:63726604110, loc:(*time.Location)(0x750f720)}}, Reason:"", Message:""}}, Message:"", Reason:"", NominatedNodeName:"", HostIP:"127.0.0.1", PodIP:"172.17.0.4", PodIPs:[]v1.PodIP{v1.PodIP{IP:"172.17.0.4"}}, StartTime:(*v1.Time)(0xc000d74220), InitContainerStatuses:[]v1.ContainerStatus(nil), ContainerStatuses:[]v1.ContainerStatus{v1.ContainerStatus{Name:"nginx-container", State:v1.ContainerState{Waiting:(*v1.ContainerStateWaiting)(nil), Running:(*v1.ContainerStateRunning)(0xc000d74200), Terminated:(*v1.ContainerStateTerminated)(nil)}, LastTerminationState:v1.ContainerState{Waiting:(*v1.ContainerStateWaiting)(nil), Running:(*v1.ContainerStateRunning)(nil), Terminated:(*v1.ContainerStateTerminated)(nil)}, Ready:true, RestartCount:0, Image:"nginx:latest", ImageID:"docker-pullable://nginx@sha256:6fff55753e3b34e36e24e37039ee9eae1fe38a6420d8ae16ef37c92d1eb26699", ContainerID:"docker://c729caca14fd6b19fb1fdbf5fe436352abd31c488a134fd5e56ee9fe7dc98eaa", Started:(*bool)(0xc000f7f1a9)}}, QOSClass:"BestEffort", EphemeralContainerStatuses:[]v1.ContainerStatus(nil)}
```

**What did you expect to happen:**
I would expect that type `time.Time` that implements stringer should be serialized using `.String()` instead of
`time.Time{wall:0x0, ext:63726604110, loc:(*time.Location)(0x750f720)}`

**Anything else you would like to add:**
[Miscellaneous information that will assist in solving the issue.]
