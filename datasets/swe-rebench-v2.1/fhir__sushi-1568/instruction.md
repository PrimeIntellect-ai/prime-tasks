Support New Syntax to Declare Multiple Versions of the Same Dependency
_**NOTE: Proposed syntax has changed since this issue was reported. See latest comment below.**_

Some IGs may need to support multiple versions of the same dependency package. To support this, the following syntax will be used:
```
 "hl7.fhir.us.core-old" : "npm:hl7.fhir.us.core@3.1.1",
 "hl7.fhir.us.core" : "6.1.0",
```

SUSHI has been identified as a core tool that will need to support this.

For more information, see: https://chat.fhir.org/#narrow/stream/179239-tooling/topic/Advance.20Notice/near/439946498

Also logged as a FHIR Package Loader issue here: https://github.com/standardhealth/fhir-package-loader/issues/23

### Additional contract requirements

- In `sushi-config.yaml`, a dependency on a specific version of a package under an alias is declared in the `dependencies` map using the form `<alias>@npm:<packageId>: <version>`, for example:

  ```
  dependencies:
    hl7.fhir.us.core: 7.0.0
    v610@npm:hl7.fhir.us.core: 6.1.0
    v311@npm:hl7.fhir.us.core: 3.1.1
  ```

  The alias is the portion of the key before `@npm:`. The aliased package is loaded under its real package id and the declared version. In the generated ImplementationGuide, the aliased dependency's `dependsOn` entry keeps the alias as its `packageId`, and its `uri` is the real package's ImplementationGuide URL.
- When multiple versions of the same package are declared, the latest version is loaded last.
- `InMemoryVirtualPackage` is available from the `fhir-package-loader` package. It is constructed as `new InMemoryVirtualPackage({ name, version }, entries)`, where `entries` is a `Map<string, any>` from resource key to resource JSON, and the resulting instance can be passed to `FHIRDefinitions.loadVirtualPackage`.


- - When `v310@npm:hl7.fhir.us.core` is declared alongside `hl7.fhir.us.core`, its generated ImplementationGuide `dependsOn` entry has a non-empty `id` different from `hl7_fhir_us_core`.
- Loading valid aliased dependencies must not emit warnings. When the alias `v610!@npm:hl7.fhir.us.core` is used, emit a warning matching `/NPM aliases should .+\. Found 'v610!'/s`.
- When skipping the version check for `v200@npm:hl7.fhir.us.core`, log exactly: `Skipping dependency version check for NPM aliased package: v200@npm:hl7.fhir.us.core`.
