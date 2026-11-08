Password-protected messages compliance issue
I added `test-feature` string to array of disallowed strings, but Android app still allows to send password-protected messages with `test-feature` subject. Maybe regex generator splits string and expects `test` and `feature` as separate words?

Browser extension implementation handles this case correctly - showing error alert.
Currently `test-feature` is in the list of disallowed strings for `@flowcrypt.com` email accounts, so you can test it with your real FlowCrypt email.
