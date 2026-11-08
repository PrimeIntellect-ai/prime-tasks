Add support for partial validation
It would be appreciated if the transaction schema could support something like "wildcard sequences" inside a `segmentType` declaration.

The idea is to skip validation of elements/composites of some segments. This can be useful when you are dealing with big "models", and you are only interested in parse and validate part of the "model".

The syntax could be something like:

```xml
<segmentType name="FOO">
    <sequence>
    	<any/>
    </sequence>
</segmentType>
```
It's similar to the "any" element in XSD (with processContents="skip"): https://www.w3schools.com/xml/el_any.asp

Thanks in advance

### Additional contract requirements

A wildcard in a `segmentType` must not disable validation of fields that are explicitly declared elsewhere in that same segment type. Those fields retain their declared type and requiredness checks.
