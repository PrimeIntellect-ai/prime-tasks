Prevent rollbar-go to start a Client by default
The library is initializing an AsyncClient , by assigning a default value to the std variable in rollbar.go

Even if one would create his own client, a default client is created and assigned to std.

This is quite problematic,  i.e. when building tests, as a go routine is started by default, preventing to to verify your application is leaking goroutines.

The only workaround at the moment is to call Close() to stop the default Client.

A way to disable this feature would be nice, i.e. when one disable the default client using SetEnabled(false).

### Additional contract requirements

Expose the package-level operation `DisableDefaultClient(destroy bool)` to stop unwanted background activity from the automatically initialized default client. Calling it with `false` must stop that activity, including terminating the default client’s background worker. No particular internal channel state is required.
