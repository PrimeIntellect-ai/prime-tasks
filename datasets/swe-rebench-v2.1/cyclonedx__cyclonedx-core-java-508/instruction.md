Deserializing `OrganizationEntity` fails when `name` is not set
Trying to deserialize the following JSON BOM:

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.6",
  "components": [
    {
      "type": "library",
      "name": "acme-library",
      "licenses": [
        {
          "license": {
            "name": "foo",
            "licensing": {
              "purchaser": {
                "organization": {
                  "contact": [
                    {
                      "name": ""
                    }
                  ]
                }
              }
            }
          }
        }
      ]
    }
  ]
}
```

Fails with:

```
Caused by: java.lang.NullPointerException: Cannot invoke "com.fasterxml.jackson.databind.JsonNode.asText()" because the return value of "com.fasterxml.jackson.databind.JsonNode.get(String)" is null
	at org.cyclonedx.util.deserializer.OrganizationalChoiceDeserializer.deserializeOrganization(OrganizationalChoiceDeserializer.java:54)
	at org.cyclonedx.util.deserializer.OrganizationalChoiceDeserializer.deserialize(OrganizationalChoiceDeserializer.java:45)
	at org.cyclonedx.util.deserializer.OrganizationalChoiceDeserializer.deserialize(OrganizationalChoiceDeserializer.java:32)
```

Because `OrganizationalChoiceDeserializer` assumes `name` to always be present, despite it not being a mandatory field according to the spec:

https://github.com/CycloneDX/cyclonedx-core-java/blob/225e7bfb3e386ace86949a34a87f887597ef88bd/src/main/java/org/cyclonedx/util/deserializer/OrganizationalChoiceDeserializer.java#L52-L54
