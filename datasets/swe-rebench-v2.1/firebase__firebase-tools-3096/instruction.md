oobCode not appearing after updateEmail is called while using emulators
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

**firebase-tools: 9.2.1**

<!-- e.g. macOS, Windows, Ubuntu -->

**Platform: macOS**

### [REQUIRED] Test case

<!-- Provide a minimal, complete, and verifiable example (http://stackoverflow.com/help/mcve) -->

```js
await testFirebaseApp.auth().createUserWithEmailAndPassword('test@email.com', 'testing');
await testFirebaseApp.auth().currentUser?.updateEmail('test1@email.com');

const oobCodes = await axios.get(`http://localhost:9099/emulator/v1/projects/project-test/oobCodes`);
```

### [REQUIRED] Steps to reproduce

<!-- Provide the steps needed to reproduce the issue with the above test case. -->

Running the code above

### [REQUIRED] Expected behavior

<!-- What is the expected behavior? -->

oobCodes contains an oobCode for test@email.com to revert the email

### [REQUIRED] Actual behavior

<!-- Run the command with --debug flag, and include the logs below. -->

The response does not contain an oobCode to revert the email. But does contain oobCodes for other actions such as resetPassword and verifyEmail

### Additional contract requirements

When an existing (non-anonymous) user's email address is changed through the
`accounts:update` endpoint, the emulator must create an OOB code of request type
`RECOVER_EMAIL` addressed to the user's previous email address, so that the change
can be reverted.

Redeeming that OOB code (via `accounts:update` with the `oobCode` field and no
`idToken`) must restore the user's previous email address and mark that email
address as verified: the response body has `emailVerified` equal to `true`. After
redemption the OOB code is consumed and no longer appears in the emulator's OOB
code listing.
