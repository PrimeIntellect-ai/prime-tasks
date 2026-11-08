--config-file param not working with this plugin
Hey there,

I figured out that the --config-file parameter isn't working anymore with this plugin. The following exception shows that this plugin tries to determine the location of the step definitions and fails because nodejs's path.join method expected a String rather than a Boolean.

My execution command: `./node_modules/.bin/cypress run --config-file "config/cypress/cypress.json"`

```
TypeError [ERR_INVALID_ARG_TYPE] [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string. Received type boolean
    at validateString (internal/validators.js:105:11)
    at Object.resolve (path.js:978:7)
    at module.exports (/var/www/thunder/web-order/node_modules/cypress-cucumber-preprocessor/lib/stepDefinitionPath.js:11:14)
    at getStepDefinitionsPaths (/var/www/thunder/web-order/node_modules/cypress-cucumber-preprocessor/lib/getStepDefinitionsPaths.js:15:38)
    at module.exports (/var/www/thunder/web-order/node_modules/cypress-cucumber-preprocessor/lib/loader.js:25:36)
    at Stream.end (/var/www/thunder/web-order/node_modules/cypress-cucumber-preprocessor/lib/index.js:25:18)
    at _end (./node_modules/through/index.js:65:9)
    at Stream.stream.end (./node_modules/through/index.js:74:5)
    at DestroyableTransform.onend (./node_modules/readable-stream/lib/_stream_readable.js:577:10)
    at Object.onceWrapper (events.js:282:20)
    at DestroyableTransform.emit (events.js:199:15)
    at endReadableNT (./node_modules/readable-stream/lib/_stream_readable.js:1010:12)
    at processTicksAndRejections (internal/process/task_queues.js:81:17)
```

I looked into the file cypressExecutionInstance.js and checked the result of ps-node's lookup function. It returns the the arguments in the wrong order and this leads to wrong value assignment and the --config-file argument is considered as flag (boolean).

```
[ { pid: '3714',
    command: '/home/fragsalat/.cache/Cypress/3.6.1/Cypress/Cypress',
    arguments:
     [ '--run-project',
       '--config-file',
       '--cwd',
       '--no-sandbox',
       '/path/to/app',
       'config/cypress/cypress.json',
       '/path/to/app' ],
    ppid: '3544' } ]
```

This results in the following config
```
{ _:
   [ '/path/to/project',
     'config/cypress/cypress.json',
     '/path/to/project' ],
  'run-project': true,
  'config-file': true,
  cwd: true,
  sandbox: false }
```

I could open the bug also in ps-node I guess but may you find a better alternative to get the process arguments.
Thanks upfront for looking into this and for your work on this plugin :)

### Additional contract requirements

- Add a public function `stepDefinitionPath()` in module `lib/stepDefinitionPath.js`. It takes no arguments and returns an absolute path (string) to the folder that contains the Cucumber step definitions.
- Resolving that folder must not depend on the Cypress configuration file or on the Cypress process arguments, so running Cypress with `--config-file` no longer breaks step-definition resolution.
- The folder is resolved from the project's cypress-cucumber-preprocessor configuration:
  - `stepDefinitions` (string) sets the step-definitions folder, resolved relative to the project root.
  - `step_definitions` (string) is accepted as a backward-compatible alias for `stepDefinitions`.
  - `nonGlobalStepDefinitions` (boolean) selects non-global mode. When it is set and neither `stepDefinitions` nor `step_definitions` is configured, the folder defaults to `cypress/integration` under the project root.
  - When none of these options is configured, the folder defaults to `cypress/support/step_definitions` under the project root.
- When `nonGlobalStepDefinitions` is set and the resolved folder does not exist, the function throws an `Error`.
