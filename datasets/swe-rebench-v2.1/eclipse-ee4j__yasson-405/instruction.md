Support for ConcurrentMap
**Is your feature request related to a problem? Please describe.**
The OpenLiberty website was recently updated to use JSON-B over JSON-P to return data from a REST API. The JSON-B object in question has a field of type ConcurrentMap. This was correctly serialized. As a parallel activity I'm writing some integration tests and for the first time tried to deserialize the JSON-B object. This failed with the following error:

    [ERROR] io.openliberty.website.it.OpenLibertyEndpointIT.testGetReleases  Time elapsed: 0.201 s  <<< ERROR!
    javax.ws.rs.client.ResponseProcessingException: Problem with reading the data, class io.openliberty.website.data.BuildData, ContentType: application/json.
	at io.openliberty.website.it.OpenLibertyEndpointIT.testGetReleases(OpenLibertyEndpointIT.java:41)
    Caused by: javax.json.bind.JsonbException: Internal error: Can not set java.util.concurrent.ConcurrentMap field io.openliberty.website.data.BuildData.builds to java.util.HashMap
	at io.openliberty.website.it.OpenLibertyEndpointIT.testGetReleases(OpenLibertyEndpointIT.java:41)

It seems a JSON-B object with a ConcurrentMap can be serialized, but cannot be deserialized. It should be possible to do both.

**Describe the solution you'd like**
Support for JSON-B fields to contain a ConcurrentMap

**Describe alternatives you've considered**
In this case I will convert to Map to get it to work. This would not work as well if I were doing concurrent updates to the map though as I'd have to use syncronization around the map.

### Additional contract requirements

- For the tested values, serialization must produce these exact JSON strings: `{"concurrentMap":{"bar":"barVal","foo":"fooVal"}}`, `{"concurrentHashMap":{"bar":"barVal2","foo":"fooVal2"}}`, `{"concurrentNavigableMap":{"bar":"barVal3","foo":"fooVal3"}}`, and `{"concurrentSkipListMap":{"bar":"barVal4","foo":"fooVal4"}}`.
