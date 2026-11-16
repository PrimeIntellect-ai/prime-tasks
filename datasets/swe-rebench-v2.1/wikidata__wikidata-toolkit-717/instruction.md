Deserializing a property with `localMedia` datatype fails
When trying to deserialize a property with `localMedia` dataype, such as this one:

```json
        {
            "pageid": 6,
            "ns": 122,
            "title": "Property:P3",
            "lastrevid": 9,
            "modified": "2022-08-07T21:40:47Z",
            "type": "property",
            "datatype": "localMedia",
            "id": "P3",
            "labels": {
                "en": {
                    "language": "en",
                    "value": "media file"
                }
            },
            "descriptions": {},
            "aliases": {},
            "claims": {}
        }
```

We fail because the deserialization of the datatype fails, because the JSON encoding of datatypes is supposedly not allowed to contain capital letters: it should match some regex:
https://github.com/Wikidata/Wikidata-Toolkit/blob/e99f19683099beae2b0f8e6c22f094495357f951/wdtk-datamodel/src/main/java/org/wikidata/wdtk/datamodel/implementation/DatatypeIdImpl.java#L110

This regex does not make much sense to me because it fails even for some datatypes that Wikidata-Toolkit is already aware of, such as `commonsMedia`.

I see various ways forward:
* Add the `localMedia` datatype to WDTK, just like #701 did it for EDTF. While that solves this exact issue, we are not solving the underlying problem and the code will fail again, should any other such datatype be introduced in the future. Datatypes are extensible so we cannot assume we know of all the datatypes in use in Wikibase instances.
* Allowing capital letters in the regex that validates JSON datatypes. While that also works, this breaks the current assumption that the two transformations between JSON datatypes and datatype URIs are inverse of each other: `localMedia` (JSON datatype) would be converted to `http://wikiba.se/ontology#LocalMedia` by `DatatypeIdImpl.getDatatypeIriFromJsonDatatype`, and then that value would be converted back to `local-media` (not `localMedia`) by `DatatypeIdImpl.getJsonDatatypeFromDatatypeIri`. Because WDTK stores datatypes internally as URIs and not as JSON strings, this means that serializing back the property above will result in an invalid datatype. [HIDDEN]

### Additional contract requirements

Property deserialization must accept unrecognized datatype tokens containing uppercase letters, including `localMedia`. Serializing a deserialized property must preserve its original datatype token exactly.
