About sending renew request to eureka server
- [ ] I have searched the [issues](https://github.com/alibaba/fescar/issues) of this repository and believe that this is not a duplicate.

### Ⅰ. Issue Description
[HIDDEN]
Eureka client(DiscoveryClient-renew()) sends renew request to the url:  myConfigEurekServerAddress/eureka/apps/<appName>/<instanceId>

There is a "/" in instanceId, so the eureka client cannot succeed to renew.

### Ⅱ. Describe what happened

  If there is an exception, please attach the exception trace:

```
Just paste your stack trace here!
```


### Ⅲ. Describe what you expected to happen

renew success.

### Ⅳ. How to reproduce it (as minimally and precisely as possible)

1. xxx
2. xxx
3. xxx

### Ⅴ. Anything else we need to know?


### Ⅵ. Environment:

- JDK version :
- OS :
- Others: my eurke server version is 1.6.2

### Additional contract requirements

The Eureka instance identifier used for renewal must be path-safe so the Eureka client can successfully renew the registered instance.
