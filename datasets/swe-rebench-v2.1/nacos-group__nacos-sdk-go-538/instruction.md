2.x 持久化实例Naming Auth签名走的httpProxy，需要cherry-pick一下1.x的Naming Auth实现
### What version of nacos-sdk-go are you using?
2.1.2

`clients/naming_client/naming_proxy_delegate.go:66`

![image](https://user-images.githubusercontent.com/3050696/200464211-a93b5821-c10b-4941-98e5-33639b7a25b9.png)

### Additional contract requirements

- Add a public method `InjectSignForNamingHttp(param map[string]string, clientConfig constant.ClientConfig)` on `NacosServer` in package `common/nacos_server`.
- When both `AccessKey` and `SecretKey` are non-empty, the method injects three entries into `param`: `"ak"` set to the access key, `"data"` set to a sign string built from the current timestamp together with the service name and, when present, the group name, and `"signature"` set to the Base64-encoded HMAC-SHA1 of that sign string computed with the secret key.
- When either credential is empty, `param` is left unchanged.

- The sign data uses the Nacos 1.x Naming Auth wire format: the current timestamp in milliseconds, followed by `@@` and the service name. When a group applies, the group name precedes the service name and is also separated by `@@`, yielding `timestamp@@groupName@@serviceName`; without a group, use `timestamp@@serviceName`.
- Naming HTTP requests for persistent instances must carry the configured Naming Auth fields when both credentials are supplied.
