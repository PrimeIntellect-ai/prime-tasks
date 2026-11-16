Jackson mapping partially incorrect
### More information

When just switching from `jollyday-jaxb` to `jollyday-jackson` in the `pom.xml` ("jaxb" is not mentioned anywhere else) as our project is using `jackson` for everything else, the calendar-related tests and the application startup fail with errors like:
```
java.lang.IllegalStateException: Cannot instantiate configuration from URL 'jar:file://[...]/jollyday-core-0.23.1.jar!/holidays/Holidays_im.xml'.
	at de.focus_shift.jollyday.jackson@0.23.1/de.focus_shift.jollyday.jackson.JacksonConfigurationService.getConfiguration(JacksonConfigurationService.java:21)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.impl.DefaultHolidayManager.doInit(DefaultHolidayManager.java:200)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.HolidayManager.init(HolidayManager.java:253)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.caching.HolidayManagerValueHandler.createValue(HolidayManagerValueHandler.java:45)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.caching.HolidayManagerValueHandler.createValue(HolidayManagerValueHandler.java:13)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.caching.Cache.lambda$get$0(Cache.java:27)
	at java.base/java.util.concurrent.ConcurrentHashMap.computeIfAbsent(ConcurrentHashMap.java:1740)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.caching.Cache.get(Cache.java:27)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.HolidayManager.createManager(HolidayManager.java:105)
	at de.focus_shift.jollyday.core@0.23.1/de.focus_shift.jollyday.core.HolidayManager.getInstance(HolidayManager.java:89)
[...]
	at java.base/java.lang.reflect.Method.invoke(Method.java:568)
	at java.base/java.util.ArrayList.forEach(ArrayList.java:1511)
	at java.base/java.util.ArrayList.forEach(ArrayList.java:1511)
Caused by: java.lang.IllegalStateException: Cannot parse holidays XML file.
	at de.focus_shift.jollyday.jackson@0.23.1/de.focus_shift.jollyday.jackson.XMLUtil.unmarshallConfiguration(XMLUtil.java:33)
	at de.focus_shift.jollyday.jackson@0.23.1/de.focus_shift.jollyday.jackson.JacksonConfigurationService.getConfiguration(JacksonConfigurationService.java:19)
	... 14 more
Caused by: com.fasterxml.jackson.databind.exc.UnrecognizedPropertyException: Unrecognized field "from" (class de.focus_shift.jollyday.jackson.mapping.FixedWeekdayBetweenFixed), not marked as ignorable (8 known properties: "descriptionPropertiesKey", "localizedType", "validFrom", "validTo", "weekday", "From", "To", "every"])
 at [Source: (sun.net.www.protocol.jar.JarURLConnection$JarURLInputStream); line: 64, column: 35] (through reference chain: de.focus_shift.jollyday.jackson.mapping.Configuration["Holidays"]->de.focus_shift.jollyday.jackson.mapping.Holidays["FixedWeekdayBetweenFixed"]->java.util.ArrayList[0]->de.focus_shift.jollyday.jackson.mapping.FixedWeekdayBetweenFixed["from"])
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.exc.UnrecognizedPropertyException.from(UnrecognizedPropertyException.java:61)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.DeserializationContext.handleUnknownProperty(DeserializationContext.java:1153)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.std.StdDeserializer.handleUnknownProperty(StdDeserializer.java:2224)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializerBase.handleUnknownProperty(BeanDeserializerBase.java:1719)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializerBase.handleUnknownVanilla(BeanDeserializerBase.java:1697)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializer.vanillaDeserialize(BeanDeserializer.java:316)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializer.deserialize(BeanDeserializer.java:177)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.std.CollectionDeserializer._deserializeFromArray(CollectionDeserializer.java:359)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.std.CollectionDeserializer.deserialize(CollectionDeserializer.java:244)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.std.CollectionDeserializer.deserialize(CollectionDeserializer.java:28)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.impl.FieldProperty.deserializeAndSet(FieldProperty.java:138)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializer.vanillaDeserialize(BeanDeserializer.java:310)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializer.deserialize(BeanDeserializer.java:177)
	at com.fasterxml.jackson.dataformat.xml@2.16.0/com.fasterxml.jackson.dataformat.xml.deser.WrapperHandlingDeserializer.deserialize(WrapperHandlingDeserializer.java:122)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.impl.MethodProperty.deserializeAndSet(MethodProperty.java:129)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializer.vanillaDeserialize(BeanDeserializer.java:310)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.deser.BeanDeserializer.deserialize(BeanDeserializer.java:177)
	at com.fasterxml.jackson.dataformat.xml@2.16.0/com.fasterxml.jackson.dataformat.xml.deser.XmlDeserializationContext.readRootValue(XmlDeserializationContext.java:104)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.ObjectMapper._readMapAndClose(ObjectMapper.java:4899)
	at com.fasterxml.jackson.databind@2.16.0/com.fasterxml.jackson.databind.ObjectMapper.readValue(ObjectMapper.java:3883)
	at de.focus_shift.jollyday.jackson@0.23.1/de.focus_shift.jollyday.jackson.XMLUtil.unmarshallConfiguration(XMLUtil.java:31)
	... 15 more

```
After fixing the mappings this still leaves errors like:
```
java.lang.IllegalArgumentException: Configuration for gb contains  multiple SubConfigurations with the same hierarchy id. null 2 times
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.impl.DefaultHolidayManager.validateConfigurationHierarchy(DefaultHolidayManager.java:255)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.impl.DefaultHolidayManager.doInit(DefaultHolidayManager.java:201)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.HolidayManager.init(HolidayManager.java:253)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.caching.HolidayManagerValueHandler.createValue(HolidayManagerValueHandler.java:45)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.caching.HolidayManagerValueHandler.createValue(HolidayManagerValueHandler.java:13)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.caching.Cache.lambda$get$0(Cache.java:27)
	at java.base/java.util.concurrent.ConcurrentHashMap.computeIfAbsent(ConcurrentHashMap.java:1708)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.caching.Cache.get(Cache.java:27)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.HolidayManager.createManager(HolidayManager.java:105)
	at de.focus_shift.jollyday.core@0.24.0-SNAPSHOT/de.focus_shift.jollyday.core.HolidayManager.getInstance(HolidayManager.java:89)
[...]
	at java.base/java.lang.reflect.Method.invoke(Method.java:568)
	at java.base/java.util.ArrayList.forEach(ArrayList.java:1511)
	at java.base/java.util.ArrayList.forEach(ArrayList.java:1511)
```
