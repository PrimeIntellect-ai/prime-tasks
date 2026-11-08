Allow scenarios without dependency changes
Currently, [HIDDEN] which are only created if you specify [some sort of dependency change](https://github.com/ember-cli/ember-try/blob/master/lib/utils/dependency-manager-adapter-factory.js#L16-L21) in your scenarios.

However, I have [a use-case](https://github.com/trentmwillis/ember-exam/issues/41) where I would like to run multiple different scenarios without changing any dependencies. This currently results in a `No dependency manager adapter` error being thrown. I can workaround this by specifying an empty dependency change (e.g., `npm: {}`), but this feels hacky.

So, I have two questions:
1. Why is there a requirement that dependency managers must be present currently?
2. Can we remove that requirement? It seems like answer should be yes since I can hack around it now anyway.

### Additional contract requirements

- Scenarios that make no dependency changes must be supported. An empty set of dependency-manager adapters must not, by itself, prevent scenario execution.
