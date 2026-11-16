UriQueryWriteable.fromQueryString does not support multi-value parameters
## Environment Details
* Helidon Version: 4.0.10
* Helidon SE

----------

## Problem Description

When using a client to make a request with multi-value query params, only the last value is retained.

## Steps to reproduce

```java
@Test
void testMultiValueQueryParam() {
    try (Http1ClientResponse response = client.get("/greet")
            .queryParam("foo", "bar1")
            .queryParam("foo", "bar2")
            .request()) {

        assertThat(response.lastEndpointUri().query().all("foo"), is(List.of("bar1", "bar2")));
        // fails because we get ["bar2"]
    }
}
```

It boils down to `UriQueryWriteable.fromQueryString`:

```java
@Test
void testFromQueryWithMultiValueParameter() {
    UriQueryWriteable uriQuery = UriQueryWriteable.create();
    uriQuery.fromQueryString("foo=bar1&foo=bar2");
    assertThat(uriQuery.all("foo"), is(List.of("bar1", "bar2")));
    // fails because we get ["bar2"]
}
```

### Additional contract requirements

- When parsing an encoded query string with repeated parameter names, retain every value in the order encountered.
- When the same query parameter is added more than once to a client request, retain all supplied values in the request URI.
