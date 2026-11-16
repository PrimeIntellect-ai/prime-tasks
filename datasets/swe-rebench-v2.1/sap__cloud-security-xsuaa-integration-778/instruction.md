Possibility of disabling xsuaaMtlsRestOperations bean if XsuaaServiceConfiguration is not provided
**Question Summary**
- client library: `spring-xsuaa` version `2.11.1`
- Environment: Cloud Foundry

We are currently in the process of changing our xsuaa bindings to `x509` credentials for our spring applications. We are also using CAP as a framework, and we have discovered a small issue regarding the `XsuaaAutoConfiguration`. For the `x509` case, a bean [`xsuaaMtlsRestOperations`](https://github.com/SAP/cloud-security-xsuaa-integration/blob/2.11.1/spring-xsuaa/src/main/java/com/sap/cloud/security/xsuaa/autoconfiguration/XsuaaAutoConfiguration.java#L104) is configured which requires a parameter of type `XsuaaServiceConfiguration`. Usually, this is not a problem but with CAP there is use case to run a Cloud Foundry task for database migration on the java application which is executed with security disabled (because it does not expose any endpoints). You can check in their docs [here](https://cap.cloud.sap/docs/java/multitenancy#deploy-main-method). In this scenario, CAP does not provide any bean of type `XsuaaServiceConfiguration` and the application startup fails with the following exception:

```
org.springframework.beans.factory.UnsatisfiedDependencyException: Error creating bean with name 'xsuaaMtlsRestOperations' defined in class path resource [com/sap/cloud/security/xsuaa/autoconfiguration/XsuaaAutoConfiguration.class]:
Unsatisfied dependency expressed through method 'xsuaaMtlsRestOperations' parameter 0; nested exception is org.springframework.beans.factory.NoSuchBeanDefinitionException:
No qualifying bean of type 'com.sap.cloud.security.xsuaa.XsuaaServiceConfiguration' available: expected at least 1 bean which qualifies as autowire candidate. Dependency annotations: {}
	at org.springframework.beans.factory.support.ConstructorResolver.createArgumentArray(ConstructorResolver.java:800)
	...
```

Would it be an option for you to only provide a bean `xsuaaMtlsRestOperations` if `XsuaaServiceConfiguration` is provided, or in other words to make `xsuaaMtlsRestOperations` conditional on bean `XsuaaServiceConfiguration`?

If you have any further questions, let me know.

Regards,
Florian
