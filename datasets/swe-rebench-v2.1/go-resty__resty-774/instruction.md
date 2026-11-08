Clone or copy of existing client
I have a use case where my application should have a global HTTP client with sane defaults for tracing, logging and error handling and then some submodules which must apply highly specific settings for only their use case.

For that I would like to copy / clone an existing client which thus inherits all of the clients settings. In other libraries / languages this is also sometimes possible by having a child-parent relationship between clients.

What would be the best way to approach this with resty? Is there a function or common solutions for this use case?

Edit: If this is *not* a present feature but of interest to people, let's discuss how that could be implemented.

### Additional contract requirements

Expose the copy operation as `(*Client).Clone() *Client`. It returns a distinct client that inherits the existing client’s settings, and changing a value setting on the copy must not change that setting on the original.
