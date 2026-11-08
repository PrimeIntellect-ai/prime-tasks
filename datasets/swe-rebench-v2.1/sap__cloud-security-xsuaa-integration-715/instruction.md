NGPBUG-163948: create/forward correlation id for external requests to identity provider
See also [here](https://jtrack.wdf.sap.corp/browse/NGPBUG-163948) we need to set x-correlation-id header for each request, we initialize, e.g. towards identity provide in the token-client lib.

Either we set the `x-correlation-id` header with a new guid or if given, we get it from org.slf4j.MDC like that
```java
MDC.get(CORRELATION_ID); // public String CORRELATION_ID = "correlation_id";
```
See also here: https://github.com/SAP/cf-java-logging-support/blob/master/cf-java-logging-support-servlet/src/main/java/com/sap/hcp/cf/logging/servlet/filter/CorrelationIdFilter.java#L44-L53

See also here (SAP-internal): https://github.wdf.sap.corp/CPSecurity/xsuaa/blob/master/uaa-security/src/main/java/org/cloudfoundry/identity/uaa/zone/XSCorrelationIdLoggingFilter.java

So, Application developers either need to intiialize the mapped diagnostic context:
```java
MDC.put(CORRELATION_ID, ((HttpServletRequest) request).getHeader("x-correlation-id"));
```
..or use this logging library: https://github.com/SAP/cf-java-logging-support

Further References:
- https://github.com/SAP-samples/cloud-bulletinboard-ads/tree/Documentation/LoggingTracing
- https://github.com/SAP-samples/cloud-bulletinboard-ads/blob/Documentation/Service2ServiceCommunication/Exercise_19_Transfer_CorrelationID.md

### Additional contract requirements

- The correlation id is transmitted in the outbound request header named `X-CorrelationID`. HTTP header names are case-insensitive, so the `x-correlation-id` spelling used above denotes the same header.
- The correlation id is read from the SLF4J mapped diagnostic context under the key `correlation_id`; when no non-empty value is present there, a newly generated UUID is used instead.
