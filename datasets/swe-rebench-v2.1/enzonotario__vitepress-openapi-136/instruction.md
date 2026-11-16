Overwrite "Try It Out" url
### What would you like?

The ability to change the default url/port for the "Try It Out" button.

### Why is this needed?

The API I'm building has different ports for different things. In my specific case, the current behavior does not invoke my api.

### How could it be implemented?

Could we possibly  have an additional env variable that overwrites the default behavior?

### Other information

_No response_

### Additional contract requirements

The default URL for Try It Out is configurable through the theme's `operation.defaultBaseUrl` setting. When an operation and its specification define no servers, requests generated for Try It Out must target this configured URL.
