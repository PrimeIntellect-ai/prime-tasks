Change extension card to 0..0 in simple extensions; value[x] to 0..0 in complex extensions
It seems FSHers have found it necessary to explicitly zero out the unused elements in extension (depending on whether it is complex or simple). Seems not to complete the publishing process unless they do this. But SUSHI should know which is which and zero out the appropriate element.

### Additional contract requirements

- When an extension uses both a value and sub-extensions, log an error at the source location of the rule that introduces the conflict. The message must be `Extension <extension name> cannot have both a value and sub-extensions`.
