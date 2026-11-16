4.x: Docs - Security http basic auth documentation mentions wrong property
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP
* JDK version: 21
* OS:
* Docker version (if applicable):

----------

## Problem Description

Current documentation uses :
 - `HttpBasicAuthProvider.EP_PROPERTY_OUTBOUND_USER` instead of `EndpointConfig.PROPERTY_OUTBOUND_ID`
 - `HttpBasicAuthProvider.EP_PROPERTY_OUTBOUND_PASSWORD` instead of `EndpointConfig.PROPERTY_OUTBOUND_SECRET`
