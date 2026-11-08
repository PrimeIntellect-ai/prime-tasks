Default component type is set to "library" for non-library submodules in multimodule Maven project
### Description

In a multimodule Maven project, some submodules are configured with the projectType: application setting in the CycloneDX Maven plugin. However, when generating the aggregated SBOM (Software Bill of Materials), these submodules still have the component type set to "library" by default. This behavior results in an incorrect component type assignment for those submodules.

### Steps to reproduce:

Create a multimodule Maven project.
Configure the CycloneDX Maven plugin in the parent POM.
In one of the submodules, set the projectType configuration to application.
Generate the aggregated SBOM using the CycloneDX Maven plugin.

### Expected behavior:
The aggregated SBOM should reflect the correct component type for each submodule based on their individual projectType configurations. Submodules configured as application should have their component type set to application.

### Actual behavior:
Submodules configured with projectType: application still have their component type set to library in the aggregated SBOM.


I also have a solution to address this issue.
