Old/new observers config exception is causing ITs to fail
Multiple ITs are failing due to exception. It looks like this was caused by #817.

```
org.apache.fluo.api.exceptions.FluoException: Failed to update shared configuration in Zookeeper
Caused by: java.lang.IllegalArgumentException: Old and new observers configuration present.  There can only be one.
```

### Additional contract requirements

Observer configuration has two mutually exclusive formats. A configuration specifying `fluo.observer.provider` uses the new format; a configuration containing legacy observer entries uses the old format. Each format must be recognized as its own format, not as the other one.
