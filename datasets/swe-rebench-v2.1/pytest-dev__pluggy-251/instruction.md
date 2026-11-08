One hookspec to many hookimpl (implementations that don't match spec function names)
This is a proposal for an enhancement.  Before I make my request, thank you for all the work associated with this project.

My use case involves the need to support any number of hook implementations, which are essentially operations for an application to perform.  For example:

- someapp_operation_do_something
- someapp_operation_do_something_else
- someapp_operation_do_something_different
... etc

Maintaining flexibility here is important for our use case.  Having to go back and create a spec every time someone wants to implement a new operation would be cumbersome.  It would be great if I could define a hookspec like:

```
    @hookspec
    def someapp_operation(self, context):
        pass
```

And then the implementations became something like this:

```
    @hookimpl(spec="someapp_operation")
    def someapp_operation_with_a_different_name(self, context):
        do_some_stuff()
```

If I happen to call an operation that doesn't exist (wasn't actually implemented), then I can deal with the AttributeError.  That being said, it gets us away from the need to maintain N specs in our application.

The other way that I was thinking that this could be handled is just having each operation implement someapp_operation, but that would probably be something like:

```
    @hookimpl
    def someapp_operation(self, operation_name, context):
        if operation_name == "some_operation_name":
            do_something()
```

This just feels really ugly to me and prone to error.

I did some initial research into _HookCaller and set_specification(), but I won't get ahead of myself until it is clear that this might be worth investigating further and that there isn't already a pattern for handling this.

Thanks again!

### Additional contract requirements

- The hook implementation marker accepts a `specname` option (default `None`). When `specname` is provided, it is used instead of the function's own name when matching the implementation to a hook specification during registration.
- Applying the marker to a function returns that same function, with the collected options recorded on it under the attribute named `<project_name>_impl` (for a marker created with project name `example`, the attribute is `example_impl`). The recorded options include the `specname` value.
- A hook implementation whose signature does not match its hook specification, or whose `specname` has no corresponding hook specification, raises `PluginValidationError` during registration or when pending registrations are finalised.
