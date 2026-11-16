Customer's phoner number is not available in API
### Problem and impact

Unable to pull customer's phone number from API

### Expected behaviour

`GET /api/v1/organizers/(organizer)/customers/` returns phone

### Steps to reproduce

1. Get customer with phone in system
2. Validate that phone is visible in UI
3. Make API call `GET /api/v1/organizers/(organizer)/customers/` and check that all fields except phone are exposed

### Screenshots

_No response_

### Link

_No response_

### Browser (software, desktop or mobile?) and version

_No response_

### Operating system, dependency versions

_No response_

### Version

_No response_
