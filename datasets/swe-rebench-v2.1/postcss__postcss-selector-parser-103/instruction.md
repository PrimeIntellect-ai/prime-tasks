Nested selector bug in lossy mode
#7 Introduced a bug in lossy mode.

It removes a 'space' combinator after a nested '&' token.

So '& .class' is parsed to '&.class', note the removal of the space.

I'll submit a PR.
