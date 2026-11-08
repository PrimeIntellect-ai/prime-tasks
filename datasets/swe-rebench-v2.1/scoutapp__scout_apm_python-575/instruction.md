Add span context manager
As per c46c79523358f88180caac77be8c5761e6482bba  - would make several pieces of integrations simpler, removing unnecessary `try/finally`

### Additional contract requirements

`TrackedRequest` exposes a `span(...)` context manager. The value yielded inside the `with` block is the span created for that context. Leaving a span context stops that span, including when the block raises an exception; nested span contexts unwind so each scope stops its own span.
