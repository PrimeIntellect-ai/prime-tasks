XML deserialization fails for `metadata>component>properties`
Deserializing a BOM in XML format fails, when it contains a metadata component that has properties defined.

The following BOM can be used to reproduce the issue:

```xml
<?xml version="1.0" encoding="utf-8"?>
<bom xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"
     serialNumber="urn:uuid:1624fa6f-aebe-4dba-8ead-f2c876c9b832" version="1"
     xmlns="http://cyclonedx.org/schema/bom/1.4">
    <metadata>
        <component type="application">
            <name>acme-app</name>
            <properties>
                <property name="foo">bar</property>
            </properties>
        </component>
    </metadata>
</bom>
```

Stacktrace:

```
com.fasterxml.jackson.databind.JsonMappingException: Cannot deserialize value of type `java.util.ArrayList<org.cyclonedx.model.Property>` from Object value (token `JsonToken.START_OBJECT`)
 at [Source: UNKNOWN; byte offset: #UNKNOWN] (through reference chain: org.cyclonedx.model.Component["properties"]) (through reference chain: org.cyclonedx.model.Bom["metadata"])
	at com.fasterxml.jackson.databind.JsonMappingException.wrapWithPath(JsonMappingException.java:402)
	at com.fasterxml.jackson.databind.JsonMappingException.wrapWithPath(JsonMappingException.java:361)
	at com.fasterxml.jackson.databind.deser.BeanDeserializerBase.wrapAndThrow(BeanDeserializerBase.java:1853)
	at com.fasterxml.jackson.databind.deser.BeanDeserializer.vanillaDeserialize(BeanDeserializer.java:316)
	at com.fasterxml.jackson.databind.deser.BeanDeserializer.deserialize(BeanDeserializer.java:177)
	at com.fasterxml.jackson.dataformat.xml.deser.WrapperHandlingDeserializer.deserialize(WrapperHandlingDeserializer.java:122)
	at com.fasterxml.jackson.dataformat.xml.deser.XmlDeserializationContext.readRootValue(XmlDeserializationContext.java:91)
	at com.fasterxml.jackson.databind.ObjectMapper._readMapAndClose(ObjectMapper.java:4825)
	at com.fasterxml.jackson.databind.ObjectMapper.readValue(ObjectMapper.java:3833)
	at org.cyclonedx.parsers.XmlParser.parse(XmlParser.java:87)
```
