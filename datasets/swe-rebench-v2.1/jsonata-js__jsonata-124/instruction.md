Handling of "undefined" input to negate operator is inconsistent?
JSONata, as a query system should be tolerant to finding ‘nothing’ as a routine thing. This is reflected by the fact that passing the `undefined` value (the Javascript value used to represent 'nothing' here) to any operator or function does not raise an error, instead just itself returning `undefined`.

For instance:
Where the path `x` is not on the context:
`x + 1 => undefined` (no error is raised)

_(To my knowledge, the only meaningful exception to this behaviour is `$exists(undefined) => false`, but there may be others)._

This behaviour is not observed by the negate operator. E.g.
`-x` raises an error (`Cannot negate a non-numeric value: undefined`).

Is this another deliberate exception to this behaviour, or is this a bug?
