[Bug] Static and Class methods are added to the example request bodies
**Describe the bug**
Class / static methods are included in the example request body.

**To Reproduce**
Create a dataclass add a class/static method to it and set it to a requestbody with `@openapi.body({"application/json": Class})`

**Expected behavior**
We pass an instance of a class so class and static methods should not be in the documentation.

**Environment (please complete the following information):**
 - OS: Pop OS 22.04
 - Browser curl
 - Version 22.3.1
