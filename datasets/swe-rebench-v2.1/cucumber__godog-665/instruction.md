Localisation supports
### 🤔 What's the problem you're trying to solve?

I was trying to write Gherkin syntax in Indonesian language as defined [in the docs.](https://cucumber.io/docs/gherkin/languages/). But I got `Parser errors` when I ran the test. Here is the example of the feature file:

```
Fitur: login

  Skenario: Login sukses
    Jika username gw adalah dokter_jakbar1
    Ketika gw login pake password 12345678
    Maka access_token ga boleh kosong
    Dan http status code harus 200

  Skenario: Username ngaco
    Jika username gw adalah dukun_santet
    Ketika gw login pake password 12345678
    Maka http status code harus 401
```
This should be correct according to the docs. And if I switched the feature file using english like this:

```
Feature: login

  Scenario: Successful login
    Given my username is dokter_jakbar1
    When I login using the password 12345678
    Then access_token should not be empty
    And http status code should be 200

  Scenario: Invalid username
    Given my username is dukun_santet
    When I login using the password 12345678
    Then http status code should be 401
```
It works as expected.

When I take a peek on the code, I couldn't find anything to switch the language to call [this gherkin go function](https://github.com/cucumber/gherkin/blob/2f55c59d59aa8db8956be82e8e30f63804b6407e/go/gherkin.go#L131). Or, am I missing something?

### ✨ What's your proposed solution?

[HIDDEN] Although, I'm not inspecting the [ParseFeatures](https://github.com/cucumber/godog/blob/c5a88f62c2a610e4581fd033f1d6f6cd05912df5/internal/parser/parser.go#L149) reference yet, whether adding parameters there would cause breaking change or not.

### ⛏ Have you considered any alternatives or workarounds?

_No response_

### 📚 Any additional context?

_No response_

### Additional contract requirements

- Add a public `Dialect string` field to the suite options (`godog.Options`). When set, it selects the Gherkin language used to parse feature files; when empty, the Gherkin default dialect (`en`) is used.
- `ParseFeatures(fsys fs.FS, filter, dialect string, paths []string) ([]*models.Feature, error)` in `internal/parser` parses feature files/directories from the supplied filesystem using the supplied dialect, defaulting to the Gherkin default dialect when `dialect` is empty.
- `ParseFromBytes(filter, dialect string, featuresInputs []FeatureContent) ([]*models.Feature, error)` in `internal/parser` parses in-memory feature definitions using the supplied dialect, defaulting to the Gherkin default dialect when `dialect` is empty.
- The dialect selected through the suite options must be applied when the suite loads its features.
