XML deserialization fails when multiple legacy `Tool`s are provided
Originally reported in the Dependency-Track repository: https://github.com/DependencyTrack/dependency-track/issues/3107

When an XML BOM contains multiple `metadata>tools>tool` nodes, deserialization fails with:

```
Caused by: com.fasterxml.jackson.databind.exc.MismatchedInputException: Cannot deserialize value of type `org.cyclonedx.model.Tool` from Array value (token `JsonToken.START_ARRAY`)
 at [Source: UNKNOWN; byte offset: #UNKNOWN]
        at com.fasterxml.jackson.databind.exc.MismatchedInputException.from(MismatchedInputException.java:59)
        at com.fasterxml.jackson.databind.DeserializationContext.reportInputMismatch(DeserializationContext.java:1752)
        at com.fasterxml.jackson.databind.DeserializationContext.handleUnexpectedToken(DeserializationContext.java:1526)
        at com.fasterxml.jackson.databind.DeserializationContext.handleUnexpectedToken(DeserializationContext.java:1473)
        at com.fasterxml.jackson.databind.deser.BeanDeserializer._deserializeFromArray(BeanDeserializer.java:656)
        at com.fasterxml.jackson.databind.deser.BeanDeserializer._deserializeOther(BeanDeserializer.java:211)
        at com.fasterxml.jackson.databind.deser.BeanDeserializer.deserialize(BeanDeserializer.java:187)
        at com.fasterxml.jackson.databind.ObjectMapper._convert(ObjectMapper.java:4539)
```

Reproducible with the following BOM:

```xml
<?xml version="1.0" encoding="utf-8"?>
<bom xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"
     serialNumber="urn:uuid:1624fa6f-aebe-4dba-8ead-f2c876c9b832" version="1"
     xmlns="http://cyclonedx.org/schema/bom/1.4">
    <metadata>
        <timestamp>2023-10-17T08:58:32.033Z</timestamp>
        <tools>
            <tool>
                <name>acme-tool-a</name>
                <version>1.0.0</version>
            </tool>
            <tool>
                <name>acme-tool-b</name>
                <version>2.0.0</version>
            </tool>
        </tools>
    </metadata>
</bom>
```
