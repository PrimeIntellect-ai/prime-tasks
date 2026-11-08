4.x Telemetry scopes are not closed properly when using baggage
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP
* JDK version:
* OS:
* Docker version (if applicable):

----------

## Problem Description
In an app that uses OpenTelemetry tracing, adding baggage disrupts the handling of scopes.

Specifically, creating a span, activating it (which creates an autocloseable `Scope`), and then adding baggage to the span within the `try` block causes the `try-with-resources` close handling for the scope to act as a no-op.

## Steps to reproduce
You do not need to start Jaeger to receive the tracing; just ignore the runtime errors about being unable to send the tracing information.

1. Create a new SE app using `helidon init` and specify custom with tracing; take the other defaults.
2. Replace the generated `TracedService.TracedHandler#handle` method with this:
   ```
        @Override
        public void handle(ServerRequest req, ServerResponse res) {
            Tracer tracer = req.context().get(Tracer.class)
                    .orElseGet(Tracer::global);
            Span span = tracer.spanBuilder("custom-span")
                    .start();
            Span.current().ifPresentOrElse(s -> System.err.println("Current span before try-with-resources: " + s.context().spanId()),
                                           () -> System.err.println("No current span before try-with-resources"));

            try (Scope scope = span.activate()) {
                Span.current().ifPresentOrElse(s -> System.err.println("Current span in try-with-resources: " + s.context().spanId()),
                                               () -> System.err.println("No current span in try-with-resources"));
                span.addEvent("my nice log");

                res.send(message);
            } finally {
                span.end();
            }
            Span.current().ifPresentOrElse(s -> System.err.println("Current span after try-with-resources: " + s.context().spanId()),
                                           () -> System.err.println("No current span after try-with-resources"));
        }
   ```
   The changes do two things:
   1. Explicitly activate the custom span in the `try`, creating an auto-closable `Scope`.
   2. Display the current span just before, just inside, and just after the `try-with-resources` block.
3. Build and run the app and run `curl http://localhost:8080/traced`. You see the expected two different current spans at the expected times:
   ```
   Current span before try-with-resources: 268165d9440e2b8f
   Current span in try-with-resources: 1cfbe8a1c629213b
   Current span after try-with-resources: 268165d9440e2b8f
   ```
5. Add the following lines after the `span.addEvent` line in `TracedService.TracedHandler#handle`:
   ```
   span.baggage("myInfo", "myValue");
   Span.current().ifPresentOrElse(s -> System.err.println("Current span after setting baggage: " + s.context().spanId()),
                               () -> System.err.println("No current span after setting baggage"));
   ```
6. Stop, rebuild, and rerun the app and run `curl http://localhost:8080/traced` again.

The output reports the same span all three times:
```
Current span before try-with-resources: f3aa5b9b91198f31
Current span in try-with-resources: d93eaba9643f0c51
Current span after setting baggage: d93eaba9643f0c51
Current span after try-with-resources: d93eaba9643f0c51
```
The scope explicitly declared in the `try` that should be auto-closed is not.

[HIDDEN]

### Additional contract requirements

- When baggage is added to an active span, closing its try-with-resources scope must restore the context that was current before the span was activated.
