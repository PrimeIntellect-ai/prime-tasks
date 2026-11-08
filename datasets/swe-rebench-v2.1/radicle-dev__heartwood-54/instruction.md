Make sure all `wire` messages fit with `64KB`
Due to the planned noise protocol framing, we need to ensure that all messages sent between peers fit within 64KB.

We should audit the code (mainly the `wire` module), find a strategy for large messages (eg. splitting them or limiting the amount of data that can go in), and if possible, add some assertions to catch any messages that are bigger than 64KB.

### Additional contract requirements

- Add a public struct `Ping` in module `radicle_node::service::message`, with public fields `ponglen: wire::Size` and `zeroes: ZeroBytes`.
- The `Message` enum variant `Ping` carries a `Ping` value: `Message::Ping(Ping)`.
- Add a public constructor `Ping::new(rng: &mut fastrand::Rng) -> Ping`. The generated `ponglen` is at most `Ping::MAX_PONG_ZEROES`, and the generated `zeroes` payload length is at most `Ping::MAX_PING_ZEROES`.
- Add public constants `Ping::MAX_PING_ZEROES: wire::Size` and `Ping::MAX_PONG_ZEROES: wire::Size`, the maximum zero-byte payload lengths for ping and pong messages respectively.
- `ZeroBytes::new(size: wire::Size) -> ZeroBytes` creates a zero-byte payload of the requested length.
- `wire::Size` is the crate's wire size type (`u16`).
- Encoding a `Message` (via the `wire::Encode` trait) whose encoded size exceeds 64KB (`wire::Size::MAX` bytes) must return an error.
