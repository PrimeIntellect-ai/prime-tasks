Device service PUT Resource handling shall normally publish an update to the Message Bus
# 🚀 Feature Request

### Relevant Package [**REQUIRED**]
This feature request is a change for the device-sdk-go handling of the PUT /device/name/{device}/{command} API.
Later will extend to the device-sdk-c.

### Description [**REQUIRED**]
Core-command's GET /device/name/{device}/{command} has an optional query parameter, ds-pushevent, which is described as "If set to yes, a successful GET will result in an event being pushed to the EdgeX system".
There is a desire for a similar capability for the matching PUT API, to notify other services of an update to the Resource(s), and to update core-data.


### Describe the solution you'd like
Change the Device SDK's PUT /device/name/{device}/{command} API handling, as normally sent by core-command,
to publish the updated Resource value(s) to the Message Bus as long as the Resource(s) are not write-only.

### Describe alternatives you've considered
The workaround today is to follow the PUT with a GET /device/name/{device}/{command} with ds-pushevent set to true, but this is just extra traffic to achieve the desired end.

The first draft of this Feature Request described adding a field to the data payload to indicate that the Resource value(s) should be published to the Message Bus. But, in discussion at the Architect's meeting, it was decided that we would almost always want to have the value published. The exception is for secrets or other write-only resources. So no need to require an additional field, and no worry that it might be omitted when it should be provided.
