WALA usage prompt lacks of " waagent -show-configuration"
We can perform "waagent -show-configuration" to get current WALA configuration,but "waagent -help"lacks of this usage prompt.

### Additional contract requirements

- The module `azurelinuxagent.agent` provides a public function `usage()` that takes no arguments and returns a string containing the full command-line usage message. The returned message includes the options `-verbose`, `-force`, `-help`, `-configuration-path`, `-deprovision`, `-register-service`, `-version`, `-daemon`, `-start`, `-run-exthandlers` and `-show-configuration`.
- The module `azurelinuxagent.agent` provides a public function `main(args)` that accepts a list of command-line arguments. Invoking it with `-help` prints the usage message to standard output.


- The usage message must not contain `-not-a-valid-option`.
