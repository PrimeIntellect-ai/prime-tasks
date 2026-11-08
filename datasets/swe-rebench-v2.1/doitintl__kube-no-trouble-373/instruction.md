Helm - namespace incorrectly assigned for Helm cluster-level resources
We incorrectly assign Chart namespace even for Cluster-level resources. These should not have a namespace:

```
__________________________________________________________________________________________
>>> Deprecated APIs removed in 1.22 <<<
------------------------------------------------------------------------------------------
KIND                       NAMESPACE     NAME                                             API_VERSION                         REPLACE_WITH (SINCE)
...
...
StorageClass               default       slow                                             storage.k8s.io/v1beta1              storage.k8s.io/v1 (1.6+)
```
