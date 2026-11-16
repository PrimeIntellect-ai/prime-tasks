An extra line break was output
/kind bug

**What steps did you take and what happened:**
[A clear and concise description of what the bug is.]


This is a log without SetLogger

```
I0217 18:17:05.411664   62273 shared_informer.go:280] Caches are synced for project-controller
I0217 18:17:05.411821   62273 shared_informer.go:280] Caches are synced for application-controller
```

This is set by SetLogger

```
2023-02-17T18:18:12.680+0800    INFO    client-go       Waiting for caches to sync for application-controller

2023-02-17T18:18:12.680+0800    INFO    client-go       Waiting for caches to sync for project-controller

2023-02-17T18:18:12.781+0800    INFO    client-go       Caches are synced for project-controller

2023-02-17T18:18:12.781+0800    INFO    client-go       Caches are synced for application-controller


```



They output a new line between them. After my investigation, I found that klog adds a new line at the end of the msg, but for the log output by the logr, the new line will be automatically added.

He can work normally under stdout, because stdout needs this newline


https://github.com/kubernetes/klog/blob/main/klog.go#L729

**What did you expect to happen:**

 Do not add new lines when using logr

```
2023-02-17T18:18:12.680+0800    INFO    client-go       Waiting for caches to sync for application-controller
2023-02-17T18:18:12.680+0800    INFO    client-go       Waiting for caches to sync for project-controller
2023-02-17T18:18:12.781+0800    INFO    client-go       Caches are synced for project-controller
2023-02-17T18:18:12.781+0800    INFO    client-go       Caches are synced for application-controller
```

**Anything else you would like to add:**
[Miscellaneous information that will assist in solving the issue.]
