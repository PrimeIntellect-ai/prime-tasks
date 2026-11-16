CORS "Internal exception in JAX-RS processing" with "null" Origin
## Environment Details
* Helidon Version: 4.0.6
* Helidon MP
* JDK version: Amazon Coretto 21.0.2 Hotspot
* OS: Windows 11

----------

I justed enabled CORS in the quickstart maven example ( add `helidon-microprofile-cors` dependency and set `cors.enabled=true`) ,then I opened a new Firefox window, opened a console and typed `fetch("http://localhost:8080/"`. This lead to a CORS security warning `Content-Security-Policy: .... ("connect-src")`.

I wanted to take a look at the headers hence I copied the network request via Firefox into a curl command and executed it:
```
curl 'http://172.18.32.1:8080/' -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0' -H 'Accept: */*' -H 'Accept-Language: de,en-US;q=0.7,en;q=0.3' -H 'Accept-Encoding: gzip, deflate, br' -H 'Origin: null'
```

This returns a `Internal exception in JAX-RS processing` and a lengthy exception in the server logs ending with:
```
Caused by: java.lang.StringIndexOutOfBoundsException: Range [0, -1) out of bounds for length 4
	at java.base/jdk.internal.util.Preconditions$1.apply(Preconditions.java:55)
	at java.base/jdk.internal.util.Preconditions$1.apply(Preconditions.java:52)
	at java.base/jdk.internal.util.Preconditions$4.apply(Preconditions.java:213)
	at java.base/jdk.internal.util.Preconditions$4.apply(Preconditions.java:210)
	at java.base/jdk.internal.util.Preconditions.outOfBounds(Preconditions.java:98)
	at java.base/jdk.internal.util.Preconditions.outOfBoundsCheckFromToIndex(Preconditions.java:112)
	at java.base/jdk.internal.util.Preconditions.checkFromToIndex(Preconditions.java:349)
	at java.base/java.lang.String.checkBoundsBeginEnd(String.java:4865)
	at java.base/java.lang.String.substring(String.java:2834)
	at io.helidon.cors.CorsSupportHelper.originLocation(CorsSupportHelper.java:425)
	at io.helidon.cors.CorsSupportHelper$RequestTypeInfo.create(CorsSupportHelper.java:390)
	at io.helidon.cors.CorsSupportHelper.requestType(CorsSupportHelper.java:375)
```

I hence would argue that the CorsSupportHelper::originLocation should be more robust to not cause these exceptions.

### Additional contract requirements

- A CORS request whose Origin header is the literal value `null` must be processed without an internal exception, and must not produce a 500 Internal Server Error response.
