externalReference:   Cannot convert 'static-analysis-report' to Enum
plugin v2.7.11 added support for custom External References via #428.

Following the [documentation](https://cyclonedx.github.io/cyclonedx-maven-plugin/external-references.html) I initially added the following to configuration section of pluginManagement entry for plugin:

```
                        <externalReferences>
                            <externalReference>
                                <type>static-analysis-report</type>
                                <url>https://foo.bar.com</url>
                                <comment>SonarQube</comment>
                            </externalReference>
                        </externalReferences>
```

...and got the following error:

```
[2024-01-29T17:15:05.211Z] [ERROR] Failed to execute goal org.cyclonedx:cyclonedx-maven-plugin:2.7.11:makeAggregateBom (default-cli) on project xxx-yyy: Unable to parse configuration of mojo org.cyclonedx:cyclonedx-maven-plugin:2.7.11:makeAggregateBom for parameter externalReference: Cannot convert 'static-analysis-report' to Enum: No enum constant org.cyclonedx.model.ExternalReference.Type.static-analysis-report -> [Help 1]
```

I then noticed line at bottom of documentation:

> Notice that the type value in the plugin configuration refers to a [CycloneDX Core (Java) library constant name](https://cyclonedx.github.io/cyclonedx-core-java/org/cyclonedx/model/ExternalReference.Type.html) corresponding to [CycloneDX type](https://cyclonedx.org/docs/1.5/json/#metadata_component_externalReferences_items_type)

...so I tried `STATIC_ANALYSIS_REPORT` for type, but got the same error.

Aside:  I do think that the value of type should match what is in the CycloneDX documentation (eg the guide) as that makes it easier to expect common behaviour across plugins from different ecosystems (gradle, etc).  This could be important when a Jenkins server is providing type as a variable at build time.
