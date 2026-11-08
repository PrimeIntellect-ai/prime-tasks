Robocop should warn when no rules are selected
Typical scenarios:

- selected non-existing rule (previously always failed, it could fail in the future)
- contradicting filters (ie select rule from RF 5 and --target-version 4)
- select with info rules and threshold set above info

All of those secnarios will disable all rules and nothing will run. There should be warning message. It should also support multiconfiguration - so execution should not be stopped, just warning printed.

### Additional contract requirements

- When the configuration in effect (command-line options or a configuration file) leaves no rules enabled, the run prints a warning whose text contains `No rule selected`.
- In a multiconfiguration run, a configuration that leaves no rules enabled prints this warning, and the remaining configurations are still linted and their issues are reported.
