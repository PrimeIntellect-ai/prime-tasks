feat: FewShotPromptTemplate
It's a clean way to have `FewShotPromptTemplate`, to implement the ConstitutionalChain, and also enable people to build prompts in that way.
[source](https://github.com/hwchase17/langchain/blob/master/langchain/prompts/few_shot.py)

I'd like to work on it.

### Additional contract requirements

Provide a reusable few-shot prompt API with this public constructor signature: `NewFewShotPrompt(examplePrompt PromptTemplate, examples []map[string]string, exampleSelector ExampleSelector, prefix, suffix string, input, partialInput map[string]interface{}, exampleSeparator string, templateFormat TemplateFormat, validateTemplate bool) (*FewShotPrompt, error)`. Its `Format(values map[string]interface{}) (string, error)` method must support callers supplying concrete examples and an individual-example `PromptTemplate`, along with prefix and suffix templates and an example separator. Formatting must render the examples and place them between the rendered prefix and suffix in the supplied order. Prefix and suffix may be omitted.
