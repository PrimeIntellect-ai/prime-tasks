[feature request] use tags for example tables for scenarios with more example tables
When I have a scenario with more example tables with different tags:
```
Scenario Outline: Test example
  Given Step with <param1>
  When Step with <param2>
  Then Result is <result>

@smoke
Examples:
| param1 | param2 | result |
| foo    | bar    | foobar |
| 1      | 2      | 3      |

@regression
Examples:
| param1 | param2 | result |
| abc    | def    | abcdef |
| z      | y      | z      |
```
I would like to run only those examples that are tagged with specific tag, for example `@smoke`.
This is possible with pure [cucumber-js](https://github.com/cucumber/cucumber-js/blob/master/docs/cli.md#tags), do they use different [tag-expressions](https://github.com/cucumber/cucumber/tree/master/tag-expressions)?
According to cucumber [documentation](https://cucumber.io/docs/cucumber/api/#tags):
Tags can be placed above the following Gherkin elements:
- Feature
- Scenario
- Scenario Outline
- Examples

I tried to run cucumber-js and it worked, but when running cypress with cypress-cucumber-preprocessor, I get an error: `We could not detect any tests in the above file. Write some tests and re-run.`

### Additional contract requirements

- When a tag is selected (for example with `TAGS=@smoke`), a Scenario Outline with several Examples blocks runs only the rows of the Examples blocks that carry that tag. Rows of Examples blocks without that tag are not run.
- Selecting a tag must not make a feature file report that it has no tests when some of its Examples blocks carry the selected tag.
