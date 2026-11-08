BOM serialisation fails for both JSON and XML
org.cyclonedx:cyclonedx-core-java:9.0.3

For XML:

javax.xml.parsers.ParserConfigurationException: org.cyclonedx.exception.GeneratorException: com.fasterxml.jackson.databind.JsonMappingException: Can not write a field name, expecting a value (through reference chain: org.cyclonedx.model.Bom["component"]->java.util.ArrayList[8]->org.cyclonedx.model.Component["purl"])

<img width="506" alt="Screenshot 2024-06-25 at 12 56 10 PM" src="https://github.com/CycloneDX/cyclonedx-core-java/assets/1503649/8b8574a9-3280-4131-a153-ff471543dab5">


For JSON, output of BomJsonGenerator::toJsonString just empty string.

can be reproduced here: https://github.com/CycloneDX/cyclonedx-gradle-plugin/pull/444

### Additional contract requirements

- When a BOM contains a component assigned an empty `LicenseChoice` (for example, via `Component.setLicenses(new LicenseChoice())`), JSON serialization must produce a nonempty document that is valid for the selected CycloneDX version.
- Under the same conditions, XML serialization must produce a nonempty document that is valid for the selected CycloneDX version.
