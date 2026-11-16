Unamed variants issue on complex enums
For example:
```rust
#[derive(DeRon, SerRon)]
pub enum SlashMode {
    Bounce = 0x10,
    Slash = 0x12,
    Loading = 0x13,
    BitStream = 0x1d,
    Transmission = 0x1a,
    Flow = 0x19,
    Flux = 0x25,
    Phantom = 0x24,
    Spectrum = 0x26,
    Hazard = 0x32,
    Interfacing = 0x33,
    Ramp = 0x34,
    GameOver = 0x42,
    Start = 0x43,
    Buzzer = 0x44,
}
```
I have additional derives that are required and the zbus ones in particular which enforce the `name = value` constraint. But that makes the `Unamed variants are not supported` error a little confusing.

This effectively prevents me moving off `serde`. Is there any other information I can provide?
