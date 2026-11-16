Roundtrip of InspectContainerResponse fails (VolumeBinds)
Seems <code>@JsonIgnore</code> does not work as expected.

Reproduction steps (use <code>ObjectMapper</code>):
1) Import <code>InspectContainerResponse</code> from an external <code>docker inspect containerId</code> output
2) Export <code>InspectContainerResponse</code> to a string
3) Import <code>InspectContainerResponse</code> again. An exception happens

Error happens during the serialization of InspectContainerResponse.volumes:
* Expected JSON output: <code>"Volumes":{}</code>
* Actual JSON output: <code>"Volumes":{"binds":[]}</code>

Error could be handled on deserialization side as well.

Exception:
```
Expected path for 'binds'in host but got '[]'.
 at [Source: java.io.StringReader@3c07e830; line: 1, column: 2244] (through reference chain: com.github.dockerjava.api.command.InspectContainerResponse["Volumes"])
com.fasterxml.jackson.databind.JsonMappingException
 at [Source: java.io.StringReader@3c07e830; line: 1, column: 2244] (through reference chain: com.github.dockerjava.api.command.InspectContainerResponse["Volumes"])
	at com.fasterxml.jackson.databind.JsonMappingException.from(JsonMappingException.java:164)
	at com.fasterxml.jackson.databind.DeserializationContext.mappingException(DeserializationContext.java:608)
	at com.github.dockerjava.api.model.VolumeBinds$Deserializer.deserialize(VolumeBinds.java:43)
	at com.github.dockerjava.api.model.VolumeBinds$Deserializer.deserialize(VolumeBinds.java:31)
	at com.fasterxml.jackson.databind.deser.SettableBeanProperty.deserialize(SettableBeanProperty.java:375)
	at com.fasterxml.jackson.databind.deser.impl.FieldProperty.deserializeAndSet(FieldProperty.java:107)
	at com.fasterxml.jackson.databind.deser.BeanDeserializer.deserializeFromObject(BeanDeserializer.java:308)
	at com.fasterxml.jackson.databind.deser.BeanDeserializer.deserialize(BeanDeserializer.java:121)
	at com.fasterxml.jackson.databind.deser.std.ObjectArrayDeserializer.deserialize(ObjectArrayDeserializer.java:147)
	at com.fasterxml.jackson.databind.deser.std.ObjectArrayDeserializer.deserialize(ObjectArrayDeserializer.java:18)
	at com.fasterxml.jackson.databind.ObjectMapper._readMapAndClose(ObjectMapper.java:2797)
	at com.fasterxml.jackson.databind.ObjectMapper.readValue(ObjectMapper.java:1943)
	at
```

### Additional contract requirements

- A JSON serialize-deserialize-serialize roundtrip of an `InspectContainerResponse` must produce the identical serialized string, including object member ordering.

- `InspectContainerResponse.getVolumes()` (in `com.github.dockerjava.api.command`) returns the container's volume bindings as a `com.github.dockerjava.api.model.VolumeBind[]`; the array is empty when the container has no volume bindings.
- `InspectContainerResponse.getVolumesRW()` (in `com.github.dockerjava.api.command`) returns the container's volume access modes as a `com.github.dockerjava.api.model.VolumeRW[]`; the array is empty when the container has no volume bindings.
- `VolumeBind.getContainerPath()` and `VolumeBind.getHostPath()` (in `com.github.dockerjava.api.model`) return the container-side and host-side paths of a volume binding.
- `VolumeRW.getVolume()` (in `com.github.dockerjava.api.model`) returns the associated `Volume`, whose `getPath()` returns the container-side path.
- `VolumeRW.getAccessMode()` (in `com.github.dockerjava.api.model`) returns an `AccessMode`, and `AccessMode.toBoolean()` returns `true` for read-write and `false` for read-only.
- The arrays returned by `getVolumes()` and `getVolumesRW()` must preserve the entry order of their corresponding `Volumes` and `VolumesRW` JSON objects.
