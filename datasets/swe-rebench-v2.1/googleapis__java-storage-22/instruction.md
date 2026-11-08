Cloud Storage: getStorageClass in SetStorageClassLifecycleAction is not visible
getStorageClass() method in SetStorageClassLifecycleAction class is only visible inside the package. Its not accessible outside the package.

I am trying to read storage class set by the lifecycle rule through SDK in the following way. looks like its not possible. Can you suggest any other alternative to access if this is not possible.

```
f (lifecycleAction.getActionType().equals(SetStorageClassLifecycleAction.TYPE)) {
     return ((SetStorageClassLifecycleAction)lifeCycleRule.getAction()).getStorageClass();
}
```

**// Compiler error : The method getStorageClass() from the type BucketInfo.LifecycleRule.SetStorageClassLifecycleAction is  not visible**


#### Environment details

OS type and version: Windows 10
Java version: JDK 11
sdk version: google-cloud-storage-1.7.8.0.jar
