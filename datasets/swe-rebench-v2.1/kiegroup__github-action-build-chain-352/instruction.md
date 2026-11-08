default for `core.getInput` is empty string rather than undefined or null
Since the default for `core.getInput` is empty string rather than undefined or null, it causes failures such as https://github.com/kiegroup/droolsjbpm-build-bootstrap/actions/runs/3931901214/jobs/6723762885 where `starting-project` is returned as `""` and not undefined which causes the action to ignore `process.env.GITHUB_REPOSITORY`

### Additional contract requirements

- Empty action inputs must be parsed as `undefined` rather than as an empty value. For string inputs the parsed field is `undefined` instead of `""`; this applies to `starting-project` (field `startProject`) and `annotations-prefix` (field `annotationsPrefix`).
- For comma-separated inputs, an empty input yields `undefined` rather than an empty array; this applies to `skip-project-checkout` (field `skipProjectCheckout`), `skip-project-execution` (field `skipProjectExecution`) and `custom-command-treatment` (field `customCommandTreatment`).
