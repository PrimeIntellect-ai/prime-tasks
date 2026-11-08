App is not starting on cloud foundry without dummy values for services.identity
Hello colleagues,

I have added all the dependencies mentioned here: https://github.com/SAP/cloud-security-xsuaa-integration/blob/main/spring-security/README.md

But did not get the application running in cloud foundry, I also tried different combinations  of the properties `sap.spring.security.hybrid.auto` and `sap.spring.security.xsuaa.flows.auto`. Because our application is only bound against csuaa I set the parameters like:

`sap.spring.security.hybrid.auto: true`
`sap.spring.security.xsuaa.flows.auto: false`

But with or without the parameters I always got an error message during startup. Without the parameters set I got a error that client ID is missing, with the parameters set, that some configuration class could not be found.

Only if I set the following properties in my application.yaml it works:

```
sap.security.services.identity:
  clientid:  irrelevant
  domains:
    - doesntmatter
```

The missing client Id did not come from the xsuaa instance, there a client Id was found, but from the IAS service configuration which was not found.
It took me several hours to find this solution and the questions are now:

1. Is there a better way without the properteies for `sap.security.services.identity` to get the application running only with binding to xsuaa?
2. If not, could you include a better way for the future?

Regards
André

**Question Summary**
If applicable, please mention:
- client library: java-security:2.11.11
- Environment: Cloud Foundry

### Additional contract requirements

- An application that is bound only to an XSUAA service instance and has no identity service configuration (no `sap.security.services.identity` properties) must start successfully with the Spring Security hybrid auto-configuration active. No dummy identity values may be needed.
- In that XSUAA-only setup, access tokens issued by XSUAA are validated as before, and tokens issued by the identity service are rejected (decoding fails with a `BadJwtException`).
- A hybrid JWT decoder can be created for XSUAA only by passing no identity service token validator (`null`) to its constructor; it then behaves as described above.
