help with regular expressions
Using version 0.6.0. I can't figure out how to incorporate regular expressions into the step function.

I'm trying to not only make 'exact' an optional word, but have the step function track whether 'exact' is included or not in the gherkin sentence. This is so my step function's logic can act on whether 'exact' was in the sentence or not.
Goal:
"Then I do a exact search" => step function parameter exactParam will store 'exact'
"Then I do a search" => step function parameter exactParam will store either null, undefined, or ''

But the following cause cypress to say "Step implementation missing for: I do a exact search":
then('I do a (exact)? search'), (exactParam) => {.... //rest of code
then('/I do a (exact)? search/'), (exactParam) => {.... //rest of code
then('^/I do a (exact)? search$/'), (exactParam) => {.... //rest of code
then('^/I do a (exact\s+)?search$/'), (exactParam) => {.... //rest of code

I also tried another simple regex example to look for a single digit in the gherkin sentence:
"Then I do 2"

But Cypress still said "step implementation missing for: I do 2"
then('I do (\d)'), (num) => {.... //rest of code
then('I do (\d+)'), (num) => {.... //rest of code
then('/I do (\d+)/'), (num) => {.... //rest of code

### Additional contract requirements

- `given(matcher, implementation)` accepts a `string` or `RegExp` matcher. When `matcher` is a `RegExp`, a step whose text matches the pattern is resolved, and the regular expression's capture groups are passed as arguments to `implementation`.


- Include `cypress/support/step_definitions/regexp.js` and `cypress/integration/RegularExpressions.feature`.
- Export `resolveAndRunStepDefinition` from `resolveStepDefinition.js`. It must accept a step object with `keyword` and `text` properties, resolve the matching step definition, and run its implementation.

- `then(matcher, implementation)` accepts a `RegExp` matcher; when a step's text matches it, the step definition resolves and its capture groups are passed to the implementation.
