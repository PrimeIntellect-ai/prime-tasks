m3db-operator updates multiple statefulsets at the same time

* What version of the operator are you running? Please include the docker tag. If using `master`, please include the git SHA logged when the operator first starts.

v0.12.1

* What version of Kubernetes are you running? Please include the output of `kubectl version`.
```
Client Version: version.Info{Major:"1", Minor:"19", GitVersion:"v1.19.4", GitCommit:"d360454c9bcd1634cf4cc52d1867af5491dc9c5f", GitTreeState:"archive", BuildDate:"2020-11-25T13:19:56Z", GoVersion:"go1.15.5", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"16", GitVersion:"v1.16.12", GitCommit:"17c50ce2d686f4346924935063e3a431360e0db7", GitTreeState:"clean", BuildDate:"2020-06-26T03:33:27Z", GoVersion:"go1.13.9", Compiler:"gc", Platform:"linux/amd64"}
```

* What are you trying to do?

Update m3db as described in: https://operator.m3db.io/getting_started/update_cluster/

I updated our m3dbcluster def then ran:
`kubectl -n m3 annotate statefulset -l operator.m3db.io/cluster=m3db operator.m3db.io/update=enabled`


* What did you expect to happen?

Each statefulset should be updated one at a time

* What happened?

m3db-rep0 ss updated first, as expected, but then the operator updated both m3db-rep1 and m3db-rep2 at the same time, which means pods across replicas are not available and we have downtime.

Here are the logs from the operator up until the issue occurred:

```
{"level":"info","ts":"2021-01-29T20:52:59.232Z","msg":"using InCluster k8s config"}
{"level":"info","ts":"2021-01-29T20:52:59.333Z","msg":"starting Operator controller","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T20:53:00.034Z","msg":"updated CRD","name":"m3dbclusters.operator.m3db.io","oldRV":"95259400","newRV":"95259400"}
{"level":"info","ts":"2021-01-29T20:53:00.530Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T20:53:00.531Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T20:53:00.531Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T20:53:02.135Z","msg":"waiting for informer caches to sync","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T20:53:02.135Z","msg":"starting workers","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T20:53:02.135Z","msg":"workers started","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T20:53:02.137Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T20:53:02.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T20:53:02.243Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T20:53:02.243Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T20:54:29.041Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T20:54:29.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:54:29.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:54:29.138Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T20:54:30.936Z","msg":"created statefulset","controller":"m3db-cluster-controller","name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T20:54:30.936Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T20:54:30.936Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T20:54:31.144Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T20:54:31.144Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T20:54:34.544Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:54:35.571Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:54:35.932Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T20:54:36.149Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:54:36.171Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0","id":{"name":"m3db-rep0-0"}}
{"level":"info","ts":"2021-01-29T20:54:36.171Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-0\", UID:\"73ab1e62-5bd5-4ed6-ab59-5acef5f86f79\", APIVersion:\"v1\", ResourceVersion:\"350747449\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T20:54:36.173Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:54:36.212Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:54:36.953Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T20:54:44.730Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:54:45.749Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:57:25.140Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:57:25.156Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T20:57:25.156Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1","id":{"name":"m3db-rep0-1"}}
{"level":"info","ts":"2021-01-29T20:57:25.156Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-1\", UID:\"a401e2d7-76dc-44f2-b3e6-89161ca7fa2f\", APIVersion:\"v1\", ResourceVersion:\"350749582\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T20:57:25.157Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T20:57:25.162Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:57:25.165Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2","id":{"name":"m3db-rep0-2"}}
{"level":"info","ts":"2021-01-29T20:57:25.165Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-2\", UID:\"a18894f7-aa8b-4ac2-b7b6-a193e4901707\", APIVersion:\"v1\", ResourceVersion:\"350749583\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T20:57:25.235Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:57:25.236Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T20:57:25.744Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T20:57:25.744Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T20:58:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T20:58:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T20:58:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T20:58:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T20:58:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T20:58:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T20:58:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T20:58:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T20:58:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T20:58:00.645Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T20:58:00.645Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:03:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:03:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:03:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:03:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:03:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:03:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:03:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:03:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:03:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:03:01.585Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:03:01.585Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:05:11.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:08:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:08:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:08:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:08:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:08:00.537Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:08:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:08:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:08:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:08:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:08:01.646Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:08:01.646Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:08:31.354Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:08:31.357Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:08:31.753Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:08:31.753Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:10:01.243Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:10:02.586Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:13:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:13:02.447Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:13:02.447Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:13:04.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:13:04.548Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:13:04.744Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:13:04.744Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:13:10.137Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:13:10.143Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:13:10.643Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:13:10.643Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:13:20.526Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:13:20.556Z","msg":"created statefulset","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:13:20.556Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:13:20.556Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:13:20.591Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:20.593Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:13:20.594Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:13:20.844Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:13:20.844Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:13:35.907Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:35.917Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:13:36.429Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:13:36.931Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:36.953Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:13:37.448Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:13:41.142Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:41.153Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:13:41.172Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0","id":{"name":"m3db-rep1-0"}}
{"level":"info","ts":"2021-01-29T21:13:41.172Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:13:41.173Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-0\", UID:\"e1e679c6-d29f-4abc-9578-c39f8d3ccf89\", APIVersion:\"v1\", ResourceVersion:\"350761809\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:13:41.177Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1","id":{"name":"m3db-rep1-1"}}
{"level":"info","ts":"2021-01-29T21:13:41.177Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-1\", UID:\"dc39007b-b6c7-40af-99f7-21b84328de8d\", APIVersion:\"v1\", ResourceVersion:\"350761811\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:13:41.177Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:41.230Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:13:41.230Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:41.230Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:13:41.242Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2","id":{"name":"m3db-rep1-2"}}
{"level":"info","ts":"2021-01-29T21:13:41.242Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:13:41.242Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:13:41.262Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1","id":{"name":"m3db-rep1-1"}}
{"level":"info","ts":"2021-01-29T21:13:41.262Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:13:41.262Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-1\", UID:\"dc39007b-b6c7-40af-99f7-21b84328de8d\", APIVersion:\"v1\", ResourceVersion:\"350761817\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:13:41.282Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-2\", UID:\"b68f04b9-ba08-42bc-ba7a-3362b79beaf6\", APIVersion:\"v1\", ResourceVersion:\"350761814\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:13:41.338Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2","id":{"name":"m3db-rep1-2"}}
{"level":"info","ts":"2021-01-29T21:13:41.338Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:13:41.338Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-2\", UID:\"b68f04b9-ba08-42bc-ba7a-3362b79beaf6\", APIVersion:\"v1\", ResourceVersion:\"350761833\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:13:41.443Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:13:41.443Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:18:00.447Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:18:00.448Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:18:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:18:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:18:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:18:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:18:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:18:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:18:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:18:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:18:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:23:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:23:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:23:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:23:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:23:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:23:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:23:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:23:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:23:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:23:00.546Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:23:00.546Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:24:16.730Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:24:16.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:27:05.602Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:27:05.606Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:27:06.046Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:27:06.046Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:27:13.483Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:27:13.488Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:27:13.543Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:27:13.543Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:28:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:28:00.538Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:28:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:28:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:28:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:28:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:28:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:28:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:28:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:28:00.844Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:28:00.844Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:28:20.164Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:31:23.940Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:31:23.950Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T21:31:24.385Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:31:24.385Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:31:30.711Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:31:30.759Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:31:30.759Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:31:30.767Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:31:31.076Z","msg":"created statefulset","controller":"m3db-cluster-controller","name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:31:31.076Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:31:31.076Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:31:31.382Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:31:31.382Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:31:43.152Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:31:43.293Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:31:43.773Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:31:44.172Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:31:44.308Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:31:50.894Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:31:51.658Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:31:51.667Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:31:51.692Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0","id":{"name":"m3db-rep0-0"}}
{"level":"info","ts":"2021-01-29T21:31:51.692Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:31:51.692Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-0\", UID:\"af6d3f05-7406-4bc1-9ba8-aff3ab8b268c\", APIVersion:\"v1\", ResourceVersion:\"350775524\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:31:51.693Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:31:51.694Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1","id":{"name":"m3db-rep0-1"}}
{"level":"info","ts":"2021-01-29T21:31:51.694Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:31:51.694Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-1\", UID:\"35ebc946-0d18-4a7b-981f-bcd48c69ebf8\", APIVersion:\"v1\", ResourceVersion:\"350775526\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:31:51.730Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2","id":{"name":"m3db-rep0-2"}}
{"level":"info","ts":"2021-01-29T21:31:51.730Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-2\", UID:\"bf8704be-c8dd-4886-b76c-34293b7cbf82\", APIVersion:\"v1\", ResourceVersion:\"350775529\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:31:51.731Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:31:51.731Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:31:51.830Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2","id":{"name":"m3db-rep0-2"}}
{"level":"info","ts":"2021-01-29T21:31:51.830Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0","id":{"name":"m3db-rep0-0"}}
{"level":"info","ts":"2021-01-29T21:31:51.830Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:31:51.830Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:31:51.830Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-2\", UID:\"bf8704be-c8dd-4886-b76c-34293b7cbf82\", APIVersion:\"v1\", ResourceVersion:\"350775534\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:31:51.831Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-0\", UID:\"af6d3f05-7406-4bc1-9ba8-aff3ab8b268c\", APIVersion:\"v1\", ResourceVersion:\"350775527\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:31:51.831Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:31:51.930Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:31:53.784Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:31:53.784Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:33:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:33:00.687Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:33:00.687Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:38:00.496Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:38:00.497Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:38:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:38:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:38:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:38:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:38:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:38:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:38:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:38:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:38:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:42:27.302Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:43:00.488Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:43:00.488Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:43:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:43:00.539Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:43:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:43:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:43:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:43:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:43:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:43:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:43:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:44:32.309Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:44:32.355Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:44:32.357Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:44:32.358Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:44:32.381Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:44:32.396Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:44:32.580Z","msg":"created statefulset","controller":"m3db-cluster-controller","name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:44:32.580Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:44:32.580Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:44:32.991Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:44:32.991Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:44:34.473Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:44:35.832Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:44:43.144Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:44:53.172Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:44:53.196Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:44:53.231Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T21:44:53.291Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:44:53.291Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:44:53.330Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1","id":{"name":"m3db-rep0-1"}}
{"level":"info","ts":"2021-01-29T21:44:53.330Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-1\", UID:\"0926148f-7c46-4938-8968-ef65ba3aed1d\", APIVersion:\"v1\", ResourceVersion:\"350785295\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:44:53.330Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:44:53.438Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2","id":{"name":"m3db-rep0-2"}}
{"level":"info","ts":"2021-01-29T21:44:53.438Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:44:53.438Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:44:53.439Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-2\", UID:\"bc2820b3-db2d-4e17-adb8-88ac7c250d3a\", APIVersion:\"v1\", ResourceVersion:\"350785298\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:44:53.439Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0","id":{"name":"m3db-rep0-0"}}
{"level":"info","ts":"2021-01-29T21:44:53.458Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2","id":{"name":"m3db-rep0-2"}}
{"level":"info","ts":"2021-01-29T21:44:53.439Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:44:53.530Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-0\", UID:\"0cf102eb-6f6a-48e4-847b-97d408b29a1b\", APIVersion:\"v1\", ResourceVersion:\"350785293\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:44:53.530Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-2\", UID:\"bc2820b3-db2d-4e17-adb8-88ac7c250d3a\", APIVersion:\"v1\", ResourceVersion:\"350785313\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T21:44:53.530Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:44:53.530Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:48:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:48:00.985Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:48:00.985Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:53:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:53:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:53:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:53:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:53:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:53:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:53:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:53:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:53:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:53:00.684Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:53:00.684Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:57:18.625Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:58:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T21:58:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:58:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T21:58:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T21:58:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T21:58:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T21:58:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T21:58:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T21:58:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T21:58:00.585Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T21:58:00.585Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T21:59:21.230Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T21:59:32.617Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:00:25.729Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:00:25.732Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T22:00:26.285Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:00:26.285Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:02:25.924Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:02:25.930Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T22:02:26.251Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:02:26.251Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:02:32.057Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:02:32.067Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-29T22:02:32.243Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:02:32.243Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:02:38.470Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T22:02:38.518Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:02:38.519Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:02:38.519Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:02:38.543Z","msg":"created statefulset","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T22:02:38.543Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:02:38.543Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T22:02:39.443Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:02:39.443Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:02:50.648Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:02:51.204Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:02:51.267Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:02:51.284Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:02:52.284Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:02:55.074Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:02:59.146Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:02:59.159Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0","id":{"name":"m3db-rep1-0"}}
{"level":"info","ts":"2021-01-29T22:02:59.159Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-0\", UID:\"16ea8c06-f0e7-4c92-b1fb-8ccca8f93996\", APIVersion:\"v1\", ResourceVersion:\"350798919\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:02:59.166Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:02:59.174Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:02:59.204Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:03:00.442Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:03:00.442Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:03:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:03:00.540Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:03:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:03:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:03:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:03:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:03:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:03:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:03:02.410Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:03:19.647Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:03:19.660Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:03:19.663Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1","id":{"name":"m3db-rep1-1"}}
{"level":"info","ts":"2021-01-29T22:03:19.663Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-1\", UID:\"64975777-1cd2-4262-989d-58bae259148c\", APIVersion:\"v1\", ResourceVersion:\"350799191\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:03:19.667Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T22:03:19.672Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:03:19.684Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:03:19.688Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2","id":{"name":"m3db-rep1-2"}}
{"level":"info","ts":"2021-01-29T22:03:19.688Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:03:19.730Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-2\", UID:\"09207392-850d-46cc-b685-b89fa22bc455\", APIVersion:\"v1\", ResourceVersion:\"350799192\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:03:19.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:03:19.736Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2","id":{"name":"m3db-rep1-2"}}
{"level":"info","ts":"2021-01-29T22:03:19.737Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-2\", UID:\"09207392-850d-46cc-b685-b89fa22bc455\", APIVersion:\"v1\", ResourceVersion:\"350799197\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:03:19.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:03:22.843Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:03:22.843Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:08:00.485Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:08:00.486Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:08:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:13:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:13:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:13:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:13:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:13:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:13:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:13:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:13:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:13:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:13:00.854Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:13:00.854Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:13:56.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:17:07.526Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:17:07.529Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T22:17:07.846Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:17:07.846Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:17:27.881Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:18:00.024Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:18:00.541Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:18:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:18:00.545Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:18:00.545Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:20:14.015Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:20:14.021Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T22:20:14.190Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:20:14.190Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:20:49.605Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-29T22:20:49.635Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:20:50.084Z","msg":"statefulset already exists","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:20:50.084Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:20:58.346Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:20:58.396Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:20:58.407Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:20:58.430Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:20:58.477Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:20:58.477Z","msg":"created statefulset","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:20:58.477Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:20:58.502Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":0,"updatedReplicas":0,"currentRevision":"","updateRevision":""}
{"level":"info","ts":"2021-01-29T22:20:58.502Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:21:14.201Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:21:14.307Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:21:14.326Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:21:14.821Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:21:15.228Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:21:19.055Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:21:19.064Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:21:19.079Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0","id":{"name":"m3db-rep2-0"}}
{"level":"info","ts":"2021-01-29T22:21:19.079Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep2-0\", UID:\"478ab64e-7729-49d7-9952-ffe4d4b58dc8\", APIVersion:\"v1\", ResourceVersion:\"350812780\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep2-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:21:19.079Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:21:19.130Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1","id":{"name":"m3db-rep2-1"}}
{"level":"info","ts":"2021-01-29T22:21:19.130Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:21:19.130Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0","id":{"name":"m3db-rep2-0"}}
{"level":"info","ts":"2021-01-29T22:21:19.130Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep2-1\", UID:\"e84b0c5f-51d2-41b5-be03-c2259bddd17c\", APIVersion:\"v1\", ResourceVersion:\"350812782\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep2-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:21:19.131Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:21:19.131Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep2-0\", UID:\"478ab64e-7729-49d7-9952-ffe4d4b58dc8\", APIVersion:\"v1\", ResourceVersion:\"350812783\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep2-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:21:19.137Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:21:19.152Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1","id":{"name":"m3db-rep2-1"}}
{"level":"info","ts":"2021-01-29T22:21:19.152Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:21:19.152Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep2-1\", UID:\"e84b0c5f-51d2-41b5-be03-c2259bddd17c\", APIVersion:\"v1\", ResourceVersion:\"350812785\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep2-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:21:21.496Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:21:39.571Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:21:39.581Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2","id":{"name":"m3db-rep2-2"}}
{"level":"info","ts":"2021-01-29T22:21:39.582Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep2-2\", UID:\"c8f9b1b3-9544-4aad-b983-2f3e3e7ec3fd\", APIVersion:\"v1\", ResourceVersion:\"350813067\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep2-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-29T22:21:39.583Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:21:39.588Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:21:39.598Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:21:39.634Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":0,"updatedReplicas":3,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-5f89d577db"}
{"level":"info","ts":"2021-01-29T22:21:39.634Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:21:39.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:23:00.254Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":0,"updatedReplicas":3,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-5f89d577db"}
{"level":"info","ts":"2021-01-29T22:23:00.254Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:23:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:28:00.253Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":0,"updatedReplicas":3,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-5f89d577db"}
{"level":"info","ts":"2021-01-29T22:28:00.254Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:28:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:28:00.542Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:28:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:28:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:28:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:28:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:28:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:28:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:28:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:33:00.254Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":0,"updatedReplicas":3,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-5f89d577db"}
{"level":"info","ts":"2021-01-29T22:33:00.254Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:33:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:33:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:33:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:33:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:33:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:33:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:33:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:33:00.544Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:33:00.544Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:33:45.211Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:35:58.464Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:36:07.409Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:38:00.253Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":0,"updatedReplicas":3,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-5f89d577db"}
{"level":"info","ts":"2021-01-29T22:38:00.253Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:38:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:38:00.543Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:38:00.544Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:38:00.544Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:38:00.545Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:38:00.545Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:38:00.545Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:38:00.545Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:38:00.545Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:38:06.411Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:38:06.415Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:38:06.427Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":1,"updatedReplicas":3,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-5f89d577db"}
{"level":"info","ts":"2021-01-29T22:38:06.427Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:39:23.874Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:39:23.878Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:39:23.892Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":2,"updatedReplicas":3,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-5f89d577db"}
{"level":"info","ts":"2021-01-29T22:39:23.892Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:39:24.366Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:39:24.371Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-29T22:39:24.734Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T22:39:24.836Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T22:39:24.836Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:43:00.430Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T22:43:00.535Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T22:43:00.535Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:43:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:48:00.534Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T22:48:00.730Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T22:48:00.730Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:48:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:53:00.336Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T22:53:00.530Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T22:53:00.530Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:53:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:53:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:53:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:53:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:53:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:53:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T22:53:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:53:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:53:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:58:00.631Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T22:58:00.734Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T22:58:00.734Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T22:58:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T22:58:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T22:58:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T22:58:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T22:58:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T22:58:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T22:58:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T22:58:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T22:58:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:03:00.334Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:03:00.434Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:03:00.434Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:03:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:03:00.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:03:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:03:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:03:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:03:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:03:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:03:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:03:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:08:00.532Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:08:00.636Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:08:00.636Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:08:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:08:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:13:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:13:00.437Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:13:00.437Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:13:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:13:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:13:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:13:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:13:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:13:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:13:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:13:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:13:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:18:00.338Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:18:00.635Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:18:00.635Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:18:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:18:00.737Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:18:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:18:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:18:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:18:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:18:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:18:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:18:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:23:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:23:00.438Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:23:00.438Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:23:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:23:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:23:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:23:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:23:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:23:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:23:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:23:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:23:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:28:00.336Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:28:00.631Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:28:00.631Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:28:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:28:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:28:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:28:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:28:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:28:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:28:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:28:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:28:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:33:00.630Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:33:00.731Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:33:00.731Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:33:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:33:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:33:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:33:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:33:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:33:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:33:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:33:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:33:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:38:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:38:00.530Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:38:00.530Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:38:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:38:00.738Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:38:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:38:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:38:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:38:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:38:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:38:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:38:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:43:00.631Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:43:00.734Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:43:00.735Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:43:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:48:00.335Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:48:00.455Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:48:00.455Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:48:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:48:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:48:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:48:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:48:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:48:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:48:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:48:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:48:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:53:00.430Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:53:00.634Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:53:00.634Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:53:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:53:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:53:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-29T23:53:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:53:00.739Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:53:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:53:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:53:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:53:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:58:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-29T23:58:00.531Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-29T23:58:00.531Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-29T23:58:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-29T23:58:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:03:00.338Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:03:00.631Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:03:00.631Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:03:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:03:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:08:00.534Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:08:00.730Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:08:00.730Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:08:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:08:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:08:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:08:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:08:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:08:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:08:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:08:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:08:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:13:00.431Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:13:00.536Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:13:00.536Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:13:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:13:00.740Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:13:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:13:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:13:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:13:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:13:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:13:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:13:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:18:00.432Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:18:00.731Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:18:00.731Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:18:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:23:00.434Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:23:00.538Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:23:00.538Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:23:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:23:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:23:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:23:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:23:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:23:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:23:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:23:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:23:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:28:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:28:00.438Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:28:00.438Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:28:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:28:00.741Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:28:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:28:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:28:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:28:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:28:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:28:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:28:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:33:00.631Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:33:00.733Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:33:00.733Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:33:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:38:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:38:00.530Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:38:00.530Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:38:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:38:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:38:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:38:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:38:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:38:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:38:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:38:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:38:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:43:00.537Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:43:00.734Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:43:00.734Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:43:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:43:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:43:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:43:00.742Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:43:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:43:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:43:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:43:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:43:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:48:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:48:00.437Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:48:00.437Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:48:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:48:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:48:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:48:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:48:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:48:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:48:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:48:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:48:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:53:00.632Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:53:00.734Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:53:00.735Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:53:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T00:53:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:53:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:53:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:53:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:53:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:53:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:53:00.743Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:53:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:58:00.431Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T00:58:00.534Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T00:58:00.534Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T00:58:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:03:00.537Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T01:03:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:03:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:03:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:03:00.830Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:03:00.830Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:03:00.830Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:03:00.830Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:03:00.830Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:03:00.930Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:03:00.930Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T01:03:00.931Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:08:00.531Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T01:08:00.638Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T01:08:00.638Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:08:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:08:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:08:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:08:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:08:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:08:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:08:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:08:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:08:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:13:00.430Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T01:13:00.532Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T01:13:00.532Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:13:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:18:00.337Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T01:18:00.637Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":20,"rv":"346276369"}
{"level":"info","ts":"2021-01-30T01:18:00.637Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:18:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:18:00.744Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:18:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:18:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:18:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:18:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:18:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:18:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:18:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:22:03.532Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T01:22:03.831Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":21,"rv":"350951844"}
{"level":"info","ts":"2021-01-30T01:22:03.831Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:22:59.541Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:22:59.735Z","msg":"updated statefulset","controller":"m3db-cluster-controller","name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:22:59.735Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:22:59.735Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:22:59.773Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:22:59.778Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:22:59.934Z","msg":"found placement","controller":"m3db-cluster-controller","currentPods":9,"placementInsts":9}
{"level":"info","ts":"2021-01-30T01:23:00.232Z","msg":"nothing to do","controller":"m3db-cluster-controller","childrensets":3,"zones":3,"generation":21,"rv":"350951844"}
{"level":"info","ts":"2021-01-30T01:23:00.232Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:23:00.239Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":3,"updatedReplicas":0,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:23:00.239Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:23:00.263Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":3,"updatedReplicas":0,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:23:00.263Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:23:00.435Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-30T01:23:00.447Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":3,"updatedReplicas":0,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:23:00.447Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:23:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:23:01.034Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-30T01:23:01.061Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":3,"updatedReplicas":0,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:23:01.061Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:23:12.152Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:23:12.168Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:23:12.179Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":0,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:23:12.179Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:23:23.150Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:23:23.187Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:23:23.194Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:23:23.211Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2","id":{"name":"m3db-rep0-2"}}
{"level":"info","ts":"2021-01-30T01:23:23.211Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-2\", UID:\"ec9e1c21-01ff-40e6-827d-26b720750b88\", APIVersion:\"v1\", ResourceVersion:\"350952912\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-30T01:23:23.213Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:23:23.230Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":1,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:23:23.230Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:23:23.249Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2","id":{"name":"m3db-rep0-2"}}
{"level":"info","ts":"2021-01-30T01:23:23.249Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-2\", UID:\"ec9e1c21-01ff-40e6-827d-26b720750b88\", APIVersion:\"v1\", ResourceVersion:\"350952914\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-30T01:23:23.249Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:28:00.265Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":1,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:28:00.265Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:28:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:28:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:28:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:28:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:28:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:28:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:28:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:28:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:28:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:31:55.179Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:33:00.278Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":1,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:33:00.278Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:33:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:33:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:33:00.745Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:33:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:33:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:33:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:33:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:33:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:33:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:34:30.670Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:34:30.691Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:34:30.693Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:34:30.707Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":3,"updatedReplicas":1,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:34:30.707Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:34:44.370Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:34:44.378Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:34:44.389Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":1,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:34:44.389Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:34:50.030Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:34:50.060Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:34:50.061Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:34:50.083Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1","id":{"name":"m3db-rep0-1"}}
{"level":"info","ts":"2021-01-30T01:34:50.083Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-1\", UID:\"337d86e7-d16f-47b7-978d-0cd2e30f5608\", APIVersion:\"v1\", ResourceVersion:\"350961583\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-1 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-30T01:34:50.090Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:34:50.092Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":2,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:34:50.092Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:34:50.113Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:38:00.267Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":2,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:38:00.267Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:38:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:43:00.267Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":2,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:43:00.267Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:43:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:43:00.747Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:43:22.768Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:46:15.123Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:46:15.143Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:46:15.158Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:46:15.197Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":3,"updatedReplicas":2,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:46:15.197Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:46:28.333Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:46:28.338Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:46:28.351Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":2,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:46:28.351Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:46:29.356Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:46:29.390Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:46:29.400Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:46:29.400Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0","id":{"name":"m3db-rep0-0"}}
{"level":"info","ts":"2021-01-30T01:46:29.400Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep0-0\", UID:\"ce1519b1-b79d-4f66-a1b9-1934f9b0ae9c\", APIVersion:\"v1\", ResourceVersion:\"350970452\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep0-0 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-30T01:46:29.407Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:46:29.422Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:46:29.435Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":3,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:46:29.435Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:46:29.448Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:46:47.633Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:48:00.266Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep0","replicas":3,"readyReplicas":2,"updatedReplicas":3,"currentRevision":"m3db-rep0-7bfdfb6c4d","updateRevision":"m3db-rep0-68db87c579"}
{"level":"info","ts":"2021-01-30T01:48:00.266Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:48:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:48:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:48:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-1"}
{"level":"info","ts":"2021-01-30T01:48:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-1"}
{"level":"info","ts":"2021-01-30T01:48:00.746Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-2"}
{"level":"info","ts":"2021-01-30T01:48:00.747Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-0"}
{"level":"info","ts":"2021-01-30T01:48:00.747Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-0"}
{"level":"info","ts":"2021-01-30T01:48:00.747Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-1"}
{"level":"info","ts":"2021-01-30T01:48:00.747Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:29.283Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep0-0"}
{"level":"info","ts":"2021-01-30T01:49:29.290Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep0"}
{"level":"info","ts":"2021-01-30T01:49:29.835Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-30T01:49:29.835Z","msg":"updated statefulset","controller":"m3db-cluster-controller","name":"m3db-rep1"}
{"level":"info","ts":"2021-01-30T01:49:29.835Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:29.873Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:29.877Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-30T01:49:30.234Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-30T01:49:30.234Z","msg":"updated statefulset","controller":"m3db-cluster-controller","name":"m3db-rep2"}
{"level":"info","ts":"2021-01-30T01:49:30.235Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:30.252Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep1","replicas":3,"readyReplicas":3,"updatedReplicas":0,"currentRevision":"m3db-rep1-c47fcbbd9","updateRevision":"m3db-rep1-788b7788c4"}
{"level":"info","ts":"2021-01-30T01:49:30.252Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:30.261Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:49:30.268Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-30T01:49:30.274Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":3,"updatedReplicas":0,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-766d8797df"}
{"level":"info","ts":"2021-01-30T01:49:30.274Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:30.281Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep1","replicas":3,"readyReplicas":3,"updatedReplicas":0,"currentRevision":"m3db-rep1-c47fcbbd9","updateRevision":"m3db-rep1-788b7788c4"}
{"level":"info","ts":"2021-01-30T01:49:30.281Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:33.601Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:49:33.608Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-30T01:49:33.620Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":2,"updatedReplicas":0,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-766d8797df"}
{"level":"info","ts":"2021-01-30T01:49:33.620Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:34.623Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:49:34.656Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:49:34.661Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep2"}
{"level":"info","ts":"2021-01-30T01:49:34.669Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2","id":{"name":"m3db-rep2-2"}}
{"level":"info","ts":"2021-01-30T01:49:34.669Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep2-2\", UID:\"aa8dcb39-1f52-4cfe-9d72-fda6518f6793\", APIVersion:\"v1\", ResourceVersion:\"350972882\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep2-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-30T01:49:34.674Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:49:34.686Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:49:34.730Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":2,"updatedReplicas":1,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-766d8797df"}
{"level":"info","ts":"2021-01-30T01:49:34.730Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:34.736Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep2-2"}
{"level":"info","ts":"2021-01-30T01:49:42.679Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:42.684Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-30T01:49:42.695Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":2,"updatedReplicas":1,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-766d8797df"}
{"level":"info","ts":"2021-01-30T01:49:42.695Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:43.697Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:43.731Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:43.742Z","msg":"processing statefulset","controller":"m3db-cluster-controller","statefulset.namespace":"m3","statefulset.name":"m3db-rep1"}
{"level":"info","ts":"2021-01-30T01:49:43.747Z","msg":"updated pod ID","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2","id":{"name":"m3db-rep1-2"}}
{"level":"info","ts":"2021-01-30T01:49:43.747Z","msg":"Event(v1.ObjectReference{Kind:\"Pod\", Namespace:\"m3\", Name:\"m3db-rep1-2\", UID:\"bcf549a8-0b4b-45ad-9156-ab51907148bd\", APIVersion:\"v1\", ResourceVersion:\"350973016\", FieldPath:\"\"}): type: 'Normal' reason: 'SuccessfulSync' updated pod m3db-rep1-2 with ID annotation","controller":"m3db-cluster-controller"}
{"level":"info","ts":"2021-01-30T01:49:43.753Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:43.833Z","msg":"waiting for statefulset to be ready","controller":"m3db-cluster-controller","name":"m3db-rep2","replicas":3,"readyReplicas":2,"updatedReplicas":1,"currentRevision":"m3db-rep2-5f89d577db","updateRevision":"m3db-rep2-766d8797df"}
{"level":"info","ts":"2021-01-30T01:49:43.833Z","msg":"successfully synced item","controller":"m3db-cluster-controller","key":"m3/m3db"}
{"level":"info","ts":"2021-01-30T01:49:43.930Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:43.930Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}
{"level":"info","ts":"2021-01-30T01:49:58.904Z","msg":"processing pod","controller":"m3db-cluster-controller","pod.namespace":"m3","pod.name":"m3db-rep1-2"}

```

### Additional contract requirements

- When the StatefulSet named `cluster1-rep0` has generation `1` and observed generation `2`, return an error with the message `set cluster1-rep0 generation is not up to date (current: 1, observed: 2)`.
