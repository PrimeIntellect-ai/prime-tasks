Firebase functions emulator ignores region
<!-- DO NOT DELETE
validate_template=true
template_path=.github/ISSUE_TEMPLATE/bug_report.md
-->

<!--
Thank you for contributing to the Firebase community!

Think you found a bug?
=======================
Yeah, we're definitely not perfect! Please use this template and include a minimal repro when opening the issue. If you know how to solve the issue, please create a Pull Request, and we'd be happy to review it!

Have a feature request?
========================
Great, we love hearing how we can improve our products! However, do not use this template to submit a feature request. Please submit your feature requests to: https://firebase.google.com/support/contact/bugs-features/

Have a usage question?
=======================
We get lots of those and we love helping you, but GitHub is not the best place for them and they will be closed. Please take a look at the guide first: https://firebase.google.com/docs/cli/

If the official documentation doesn't help, try asking through our official support channel: https://firebase.google.com/support/

Additional locations to check for solutions or assistance from the community:
- Stack Overflow: https://stackoverflow.com/
- Firebase Slack Community: https://firebase.community/

*Please avoid duplicate posting across multiple channels!*
-->

### [REQUIRED] Environment info

<!-- What version of the Firebase CLI (`firebase-tools`) are you using? Note that your issue may already be fixed in the latest versions. The latest version can be found at https://github.com/firebase/firebase-tools/releases -->

<!-- Output of `firebase --version` -->

**firebase-tools:**
9.2.0
<!-- e.g. macOS, Windows, Ubuntu -->

**Platform:**
macOS
### [REQUIRED] Test case

<!-- Provide a minimal, complete, and verifiable example (http://stackoverflow.com/help/mcve) -->
`export const api = region('europe-west3').https.onRequest(server);`

When starting the emulator, the emulator correctly outputs the following URL:

`✔  functions[api]: http function initialized (http://localhost:5000/**[some-project]**/europe-west3/api).`

However, when visiting that URL, a 404 is given. Going to the following URL works however:

`http://localhost:5000/**[some-project]**/us-central1/api`

### [REQUIRED] Steps to reproduce
See above
<!-- Provide the steps needed to reproduce the issue with the above test case. -->

### [REQUIRED] Expected behavior
Hitting the `europe-west3` URL working like the `us-central1` version does.
<!-- What is the expected behavior? -->

### [REQUIRED] Actual behavior
The `europe-west3` version hits a 404, while `us-central1` works.
<!-- Run the command with --debug flag, and include the logs below. -->

Clound Functions Emulator Not handling query parameters for functions deployed locally.
When deploying functions locally using the emulator, any time a request is to a function and the URL used to make that request has query parameters, the response is HTTP 400 error.

The following function was used:
```
export const helloWorld = functions.https.onRequest((req,res) => {
    console.log(req.query);
    res.send("Hello World");
});
```

When requesting this function using the url:
http://localhost:5001/{projectName}/{location}/helloWorld?id=test

I get a 400 error and in the emulator log the following happens:
function[helloWorld]
Beginning execution of "helloWorld"
14:52:13
W
function[helloWorld]
Your function timed out after ~60s. To configure this timeout, see
      https://firebase.google.com/docs/functions/manage-functions#set_timeout_and_memory_allocation.
14:52:13
I
function[helloWorld]
C:\Users\Ansaar Dollie\AppData\Roaming\npm\node_modules\firebase-tools\lib\emulator\functionsEmulatorRuntime.js:640
14:52:13
I
function[helloWorld]
            throw new Error("Function timed out.");
14:52:13
I
function[helloWorld]
            ^
14:52:13
I
function[helloWorld]

14:52:13
I
function[helloWorld]
Error: Function timed out.
14:52:13
I
function[helloWorld]
    at Timeout._onTimeout (C:\Users\Ansaar Dollie\AppData\Roaming\npm\node_modules\firebase-tools\lib\emulator\functionsEmulatorRuntime.js:640:19)
14:52:13
I
function[helloWorld]
    at listOnTimeout (internal/timers.js:554:17)
14:52:13
I
function[helloWorld]
    at processTimers (internal/timers.js:497:7)

Firebase Tools version: 9.2.0

### Additional contract requirements

- After routing an emulated HTTP function request, `req.baseUrl` must be `""`; `req.url` and `req.originalUrl` must be `"/?a=1&b=2"` for a request with query string `?a=1&b=2`, and `"/"` for a request without a query string.
