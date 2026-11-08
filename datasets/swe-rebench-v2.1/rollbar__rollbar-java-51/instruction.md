Exception in Body.fromError(Throwable)
I get the following Exception when creating a custom Payload from a Throwable:
`com.rollbar.utilities.ArgumentNullException: 'filename' cannot be null`.

I do not understand why the Frame class calls `com.rollbar.utilities.Validate.isNotNullOrWhitespace` during construction. The Throwable which is passed could have StackTraceElements assigned whose filename is set to null.

As a workaround I currently rewrite the StackTraceElements of my Throwables to substitute a null filename with a String such as "[unknown]". But I think the framework should do this.

What do you think?

Here is the full StackTrace without workaround applied:
```
com.rollbar.utilities.ArgumentNullException: 'filename' cannot be null
	at com.rollbar.utilities.Validate.isNotNullOrWhitespace(Validate.java:20)
	at com.rollbar.payload.data.body.Frame.<init>(Frame.java:65)
	at com.rollbar.payload.data.body.Frame.fromStackTraceElement(Frame.java:106)
	at com.rollbar.payload.data.body.Frame.fromThrowable(Frame.java:88)
	at com.rollbar.payload.data.body.Trace.fromThrowable(Trace.java:50)
	at com.rollbar.payload.data.body.Body.trace(Body.java:61)
	at com.rollbar.payload.data.body.Body.fromError(Body.java:49)
	at com.rollbar.payload.data.body.Body.fromError(Body.java:34)
```

### Additional contract requirements

When a Throwable contains a stack-trace frame with a null filename, creating a body from that Throwable must not throw. The corresponding serialized frame must include a non-empty string indicating an unknown filename; the particular placeholder text is not prescribed.
