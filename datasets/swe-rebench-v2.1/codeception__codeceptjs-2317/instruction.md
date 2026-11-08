Gherkin: duplicated steps generated with `gherkin:snippets`
#### What are you trying to achieve?
When I generate steps with `gherkin:snippets` command I do not want to have duplicated steps.
Problem appears when we have more than one scenario in feature, e.g.
```
  Scenario: Login to website
    Given I open a browser on a site
    When I click login button at 1.2
    Then I see welcome message

  Scenario: Logout from website
    Given I open a browser on a site
    And I click login button at 1.2
    And I see welcome message
    When I click logout
    Then I see goodbye message
```

#### What do you get instead?
Step `I open a browser on a site` appears twice in `steps.js` file
### Details

* CodeceptJS version: 2.6
* NodeJS Version: 13.11.0

### Additional contract requirements

- The `gherkin:snippets` command accepts a `--dry-run` flag that writes the generated snippets to standard output instead of a file, and a `--config` flag that selects the CodeceptJS configuration file for the command.
