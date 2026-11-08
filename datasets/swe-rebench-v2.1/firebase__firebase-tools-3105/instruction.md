Dynamic content functions redirect in emulators to :5001 port instead of :5000
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

<!-- Output of `firebase --version` -->

**firebase-tools:** 9.1.0

<!-- e.g. macOS, Windows, Ubuntu -->

**Platform:** macOS

### [REQUIRED] Test case

- Setup serving dynamic content with firebase hosting as per firebase documentation (using Express).
- Trigger a function by navigating in browser to localhost:5000/test
- Return res.redirect("/destination")  at in the express function
- User navigated to localhost:5001/destination
- User gets 404 error (expected for localhost:5001/destination as nothing is there)

<!-- Provide a minimal, complete, and verifiable example (http://stackoverflow.com/help/mcve) -->

### [REQUIRED] Steps to reproduce
See above
<!-- Provide the steps needed to reproduce the issue with the above test case. -->

### [REQUIRED] Expected behavior

Expect the redirect to use the :5000 port to navigate the user to: localhost:5000/destination
NOTE - when deployed to live, this redirect works fine. Only when operating in the emulator do the ports seem to get muddled up.

### [REQUIRED] Actual behavior

Redirects to localhost:5001/destination.

I understand this is because the functions emulator is running at :5001, however production redirects to the hosting path without any issues.

Is there either a fix to be done to the emulator, or a way I can tell express to use :5000 port instead of :5001 ?

### Additional contract requirements

- The Hosting emulator must preserve a function's `Location` response header exactly as returned, including `/over-here`.
