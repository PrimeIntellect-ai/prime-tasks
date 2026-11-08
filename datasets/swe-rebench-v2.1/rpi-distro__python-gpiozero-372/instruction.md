Alias "amber" to "yellow" for American users
When teaching with gpiozero at Picademy USA, I discovered that they commonly refer to the middle light as "yellow", rather than "amber".

I suggest we add an alias for this.

@mrichardson23

### Additional contract requirements

- `TrafficLights` accepts a `yellow` keyword argument as an alias for `amber`. Supplying both `amber` and `yellow` is an error.
- Reading the `amber` or `yellow` attribute returns the middle LED, regardless of which of the two names was supplied when the board was constructed.
- Assigning to the `amber` or `yellow` attribute resolves the alias to the name supplied when the board was constructed; because the LEDs are read-only, the assignment is rejected with an `AttributeError`.
