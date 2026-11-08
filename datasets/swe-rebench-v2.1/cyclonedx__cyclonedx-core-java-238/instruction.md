Error in ExternalReferenceSerializer
When writing an ExternalReference to xml or json, you check the url string by using "[HIDDEN]".
If this call throws an Exception the ExternalReference is skipped.
This is not correct. Java only accepts urls, for which it has a protocol handler. On every other url Java throws a MalformedURLException.
So you may have a correct url, but Java does not know the protocol and throws a exception.
Because of this test, ExternalReferences with valid urls are skipped.
So you should just write out the ExternalRefererence as it is.

### Additional contract requirements

- When serializing to JSON or XML, do not skip a valid external reference solely because its URL scheme has no Java URL protocol handler; preserve the reference and its URL.
