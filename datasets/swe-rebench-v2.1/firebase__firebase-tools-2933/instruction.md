Error emulating the method generateEmailVerificationLink (auth emulator) - The provided ID token is not a valid Firebase ID token.
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

**firebase-tools: 8.16.2**

<!-- e.g. macOS, Windows, Ubuntu -->

**Platform: macOS Big Sur 11.0.1, Node.js 12.19.0**

### [REQUIRED] Test case

<!-- Provide a minimal, complete, and verifiable example (http://stackoverflow.com/help/mcve) -->
Error emulating the method `generateEmailVerificationLink`:
```FirebaseAuthError: There is no user record corresponding to the provided identifier.```

### [REQUIRED] Steps to reproduce

<!-- Provide the steps needed to reproduce the issue with the above test case. -->
- Create User: ```admin.auth().createUser({email: 'test@test.com'});```
- Generate email verificaation link: ```admin.auth().generateEmailVerificationLink("test@test.com");```

### [REQUIRED] Expected behavior

<!-- What is the expected behavior? -->
Resolve string (url)

### [REQUIRED] Actual behavior

<!-- Run the command with --debug flag, and include the logs below. -->
Reject with error: ```FirebaseAuthError: The provided ID token is not a valid Firebase ID token.```

### Additional contract requirements

- For an email verification link request with `returnOobLink: true`, return the error message `MISSING_EMAIL` when no email is supplied, and `USER_NOT_FOUND` when the supplied email has no user record.
