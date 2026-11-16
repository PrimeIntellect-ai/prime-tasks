`ObjectLocator` doesn't work when BOM doesn't have a `metadata.component` node
`ObjectLocator#locate` does not search *any* objects in a given BOM, if the BOM is missing a `metadata.component` node:

https://github.com/CycloneDX/cyclonedx-core-java/blob/e2f7db69fda60632ce759fbf293b8bdf3754cd91/src/main/java/org/cyclonedx/util/ObjectLocator.java#L64-L90

It should be able to search in `components`, `services`, and `vulnerabilities`, even when `metadata.component` is not set.
