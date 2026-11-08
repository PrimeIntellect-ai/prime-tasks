Helidon 4.0.5 fails during HTTP/2 connection upgrade due to wrong Base64 decoding
## Environment Details
* Helidon Version: 4.0.5
* Helidon SE
* JDK version: Zulu 21.0.1
* OS: 6.1.71-1-MANJARO
* Docker version (if applicable): -

----------

I am trying to run a benchmark using Hyperfoil and Helidon 4.0.5 BUT Helidon returns 500 error during H2C connection upgrade (benchmark runs OK when using HTTP 1.1. HTTP2 server properly configured with dependency in pom.xml and tested with curl.


 Helidon shows this error message in the logs:

```
2024.02.20 09:09:28.091 Internal server error
io.helidon.http.RequestException: Internal error
	at io.helidon.http.RequestException$Builder.build(RequestException.java:139)
	at io.helidon.webserver.http1.Http1Connection.handle(Http1Connection.java:227)
	at io.helidon.webserver.ConnectionHandler.run(ConnectionHandler.java:165)
	at io.helidon.common.task.InterruptableTask.call(InterruptableTask.java:47)
	at io.helidon.webserver.ThreadPerTaskExecutor$ThreadBoundFuture.run(ThreadPerTaskExecutor.java:239)
	at java.base/java.lang.VirtualThread.run(VirtualThread.java:309)
Caused by: java.lang.IllegalArgumentException: Illegal base64 character 5f
	at java.base/java.util.Base64$Decoder.decode0(Base64.java:852)
	at java.base/java.util.Base64$Decoder.decode(Base64.java:570)
	at io.helidon.webserver.http2.Http2Upgrader.upgrade(Http2Upgrader.java:80)
	at io.helidon.webserver.http1.Http1Connection.handle(Http1Connection.java:177)
	... 4 more

```
I think the problem is that Helidon is NOT able to properly handle the HTTP2-Settings header. According to the RFC ( https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-http2-07#page-10) , HTTP"-Settings is encoded as a URL- and filename-safe Base64 encoding. That means that "_" is a valid char in this alphabet. But looks to me that Helidon is using plain Base64 that is wrong according to the specs.


![wireshark](https://github.com/helidon-io/helidon/assets/3510476/4ddb8018-4d0d-47f3-8ac9-924c9c73c7d1)

In this case, the HTTP2-Setting headers as produced by Hyperfoil is AAEAABAAAAIAAAABAAN______AAQAAP__AAUAAEAAAAYAACAA, that is valid one according to specs. I attach a picture with the proper detail of the Wireshark capture to illustrate the issue.

[HIDDEN]

I am using hyperfoil 0.24.1 with this config file to easily reproduce the issue:


```
name: helidonConstantRate
threads: 2
http:
  host: http://localhost:8080
  sharedConnections: 100
  allowHttp1x: false
  maxHttp2Streams: 100
ergonomics: # Disable stopping the scenario on 4xx or 5xx response
  autoRangeCheck: false
phases:
- helidon:
    constantRate:
      usersPerSec: 2000
      duration: 120s
      maxDuration: 180s
      scenario:
      - search:
        - httpRequest:
            GET: /simple-greet

```

UPDATE: I tested the recommended fix and it works as expected!!!!
