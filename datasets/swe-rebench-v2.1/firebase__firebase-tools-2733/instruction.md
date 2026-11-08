Error: Hosting target (project-name) not detected in firebase.json
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

**firebase-tools:**v8.13.1

<!-- e.g. macOS, Windows, Ubuntu -->

**Platform:**macOS

### [REQUIRED] Test case

`firebase deploy --only hosting:(project-name)`

<!-- Provide a minimal, complete, and verifiable example (http://stackoverflow.com/help/mcve) -->

### [REQUIRED] Steps to reproduce

I'm using the following Github action: https://github.com/w9jds/firebase-action/ which uses the latest release of firebase-tools.
Since the last update, it's not working anymore. I had to manually set to an older version of firebase-tools (I went for v8.12.1, I haven't tried with v8.13.0)

<!-- Provide the steps needed to reproduce the issue with the above test case. -->

### [REQUIRED] Expected behavior

Successful deploy
<!-- What is the expected behavior? -->

### [REQUIRED] Actual behavior
Deploy error
Error: Hosting target (project-name) not detected in firebase.json

<!-- Run the command with --debug flag, and include the logs below. -->

### Additional contract requirements

When a Hosting site is represented by a `site` field in a Hosting configuration, that site name may be supplied as the value after `hosting:` in `--only`; deployment should select the matching configuration.
