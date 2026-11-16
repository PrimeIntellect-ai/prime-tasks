Add resource, command, and device tags to reading/event
<!--🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅

Oh hi there! 😄

To expedite issue processing please search open and closed issues before submitting a new one.
Existing issues often contain information about workarounds, resolution, or progress updates.

Please do not remove sections of this template when submitting your issue.  If the section is not relevant to your issue, leave the section but enter "n/a" for not applicable.

Note some sections are marked "REQUIRED" and must be provided.  Never mark required sections "n/a".

🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅-->


# 🚀 Feature Request

### Relevant Package [**REQUIRED**]
<!-- Can you pin-point one or more EdgeX services the are relevant for this feature request? -->
<!-- ✍️edit: --> device-sdk


### Description [**REQUIRED**]
Based on https://github.com/edgexfoundry/go-mod-core-contracts/issues/767
Device, device resource, and device command now have the `Tags map[string]interface{}` field that allows users to provide additional information. device-sdk should add these tags to reading/event.
### Describe the solution you'd like
Before sending out an event, do the following:
1. Add device resource tags in reading level
2. Add device command tags in event level
3. Add device tags in event level

The device tags should take precedence over the device command tags if the tag name is the same.

### Describe alternatives you've considered
<!-- ✍️--> Have you considered any alternative solutions or workarounds?
