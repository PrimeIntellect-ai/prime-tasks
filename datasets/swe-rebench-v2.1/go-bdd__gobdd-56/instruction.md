Formalize AddStep
**Is your feature request related to a problem? Please describe.**
Currently the first parameter of `AddStep` allows passing various types:

- `string`
- `[]byte`
- `*regexp.Regex`

I think the API here could be improved a bit. It's easier to code when functions have definitive types.

**Describe the solution you'd like**
I think the most common usage is `suite.AddStep(`some string step definition`)`, so I would make the first parameter `string`.

I don't really see why would anyone use a byte slice here. Are there any use cases for that? Maybe we could remove this one.

Finally I would add a `suite.AddRegexStep` function for accepting a regex instance.


**Additional context**
I understand this is just polishing, and in a testing use case using reflection doesn't matter that much, but having an easy to read and understand API makes using the library easier.

WDYT?
