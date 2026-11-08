Unable to get Span without consuming Pair
If getting a Span consumes a Pair, I have to choose between getting that Span and getting its inner Pairs. This is counter intuitive given that the two don't really seem related. Sometimes I want to look further into the contents of a pair and also get its position. Can we add a `span(&self)` method (or something) to get the Span of a Pair and still allow you to get its inner Pairs afterwards?

I would be happy to create a PR for this. :smile:

### Additional contract requirements

- `Pair` must provide a method named `as_span` with the signature `as_span(&self) -> Span<'i>`. It returns the `Span` of the input matched by the pair (same position and text as the pair's span).
- Calling `as_span` must not consume the pair: after calling it, the same pair can still be used, for example to call `into_inner()` and iterate its inner pairs.
