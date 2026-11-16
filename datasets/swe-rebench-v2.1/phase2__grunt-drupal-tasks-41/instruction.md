Create a facility to support multiple environments
During the primary build of a project there are often multiple domains basepaths. Development, QA, Demo, Production, Feature-branch instances, and so on. Any of these might need meaningful behat and other sorts of testing processes.

We need a method to make the basepath adapative or swappable via configuration. Making basepath a default configuration with overrides from command-line might be the most natural, for example: ```grunt --env=grayside.example.com``` or ```GRUNT_BASEPATH=grayside.example.com```. The latter leverages environment parameters, which may allow for automating how this happens without explicit developer action.

### Additional contract requirements

The `lib/init.js` module is callable with the project's Grunt instance and
returns a facility with a `domain()` accessor. The accessor resolves the
effective domain from the `GDT_DOMAIN` environment variable, falling back to
the project's `config.domain` value and then to the operating system hostname.
Calling the returned facility's `init()` method must publish the effective
domain as `config.domain` in the project configuration.
