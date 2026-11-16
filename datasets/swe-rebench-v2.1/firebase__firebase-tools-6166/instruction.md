firebase deploy crashes due to next.js image optimization check, version 12.4.5
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

**firebase-tools:** 12.4.5

The issue seems to have been introduced with commit 7d2a90e6063937daaef9c9a882339991570584e2

<!-- e.g. macOS, Windows, Ubuntu -->

**Platform:** ubuntu-lastest (FirebaseExtended/action-hosting-deploy@v0)

### [REQUIRED] Test case

<!-- Provide a minimal, complete, and verifiable example (http://stackoverflow.com/help/mcve) -->

Proprietary source code using "next/image" (image optimization with Node.js), hosted on firebase using Firebase Hosting and Firebase Functions. The code is built using GitHub Actions and deployed using FirebaseExtended/action-hosting-deploy@v0, which uses the latest firebase-tools version. The GitHub Actions job config is below.

![Screenshot 2023-07-20 005700](https://github.com/firebase/firebase-tools/assets/8747511/a2d7ad0d-3a0b-45ca-b893-036a826fcc82)

### [REQUIRED] Steps to reproduce

<!-- Provide the steps needed to reproduce the issue with the above test case. -->

1. Run the FirebaseExtended/action-hosting-deploy@v0 GitHub action, which pulls the latest firebase-tools version, in this case 12.4.5
2. action-hosting-deploy runs firebase deploy
3. firebase deploy crashes in **_isUsingNextImageInAppDirectory_**


### [REQUIRED] Expected behavior

<!-- What is the expected behavior? -->

firebase deploy should run successfully and identify Next.js image optimization occurences.

**Note:** even with the previous version (12.4.4), firebase-tools does not identify the usage of the image optimization in my private repository and I have to create an empty server action for the image optimization to work, otherwise it does not identify the image optimization usage and does not generate a firebase function. If I create an empty server action, then a function is generated and image optimization works as a result of the function being generated for a different purpose

### [REQUIRED] Actual behavior

<!-- Run the command with --debug flag, and include the logs below. -->

firebase deploy crashes with the stack trace shown below

![Screenshot 2023-07-20 005207](https://github.com/firebase/firebase-tools/assets/8747511/0b473b8e-a5fc-4eda-b92b-afa614c12346)
