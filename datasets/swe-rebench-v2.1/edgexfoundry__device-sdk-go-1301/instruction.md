Remove UseMessageBus config in 3.0
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
<!-- ✍️edit: --> This feature request is for...
all device services

### Description [**REQUIRED**]
<!-- ✍️-->
The message bus is always used after 3.0

### Describe the solution you'd like
<!-- ✍️-->
remove the config `UseMessageBus`


### Describe alternatives you've considered
<!-- ✍️--> Have you considered any alternative solutions or workarounds?

### Additional contract requirements

- The removed setting is the device service configuration setting `Device.UseMessageBus`; it must no longer be part of the device service configuration.
