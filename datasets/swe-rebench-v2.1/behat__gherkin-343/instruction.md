Background should not be allowed after the first Scenario
We currently parse the Background and Scenario out of a file like this:

```
Feature: Whatever

   Scenario: Something
     Then I should fail

   Background:
     Given I am in the wrong sequence
```

However, cucumber/gherkin will report this as a parse error, because it does not allow Background nodes after the first Scenario.

There is not yet any testdata for this case, either here or upstream.

See #323
