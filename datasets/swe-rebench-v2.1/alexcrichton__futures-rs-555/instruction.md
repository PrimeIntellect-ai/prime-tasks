Ergonomics of channel send
Consider this code:

```rust
use futures::*;

fn main() {
    let (mut tx, rx) = futures::sync::mpsc::unbounded();
    tx.send(1);
}
```
You might think this is actually sending the message on the channel, but it's not because `Sink` has been imported via the glob import (and I'd imagine most users are using the glob import) so it's calling `Sink::send` not `UnboundedSender::send` (since `UnboundedSender` impls `Sink`).

We'd have to use UFCS instead:

```rust
fn main() {
    let (mut tx, rx) = futures::sync::mpsc::unbounded();
    UnboundedSender::send(&mut tx, 1).unwrap();
}
```

I guess the compiler warnings will lead the user to fix the code, but figured I would at least document it here.

### Additional contract requirements

An unbounded sender must provide an unambiguous direct-send operation named `unbounded_send`. Calling `unbounded_send(message)` sends the message immediately and returns success when the receiver is still open; this operation remains directly callable when `Sink` is in scope, so callers need not rely on the potentially confusing `send` method.
