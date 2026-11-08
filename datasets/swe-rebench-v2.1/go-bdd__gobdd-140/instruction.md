Add current test, scenario and step to Context
**Is your feature request related to a problem? Please describe.**
1. I am using VCR library to record requests from client library to server and I would like to use correct cassette name depending from which scenario/step the request has been made.
2. I would like to create tracing span for each step and have them grouped by scenario.

**Describe the solution you'd like**
Add information about current test, scenario and step to context.

https://github.com/go-bdd/gobdd/blob/master/gobdd.go#L307

**Describe alternatives you've considered**
`-`

**Additional context**
See https://pytest-bdd.readthedocs.io/en/latest/#hooks

### Additional contract requirements

- Add a public type `FeatureKey struct{}` in package `gobdd`. While a scenario is running, the context must make the feature currently being executed available under this key: `Context.Get(FeatureKey{})` returns the `*msgs.GherkinDocument_Feature` for that feature.
- Add a public type `ScenarioKey struct{}` in package `gobdd`. While a scenario is running, the context must make the scenario currently being executed available under this key: `Context.Get(ScenarioKey{})` returns the `*msgs.GherkinDocument_Feature_Scenario` for that scenario.
