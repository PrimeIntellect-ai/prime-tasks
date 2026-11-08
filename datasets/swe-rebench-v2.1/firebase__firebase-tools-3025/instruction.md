Firebase serve fails to rewrite URL to containerized app after 8.18.0
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


$ npx firebase --version
9.1.2

<!-- e.g. macOS, Windows, Ubuntu -->

**Platform:**

macOS

### [REQUIRED] Test case

<!-- Provide a minimal, complete, and verifiable example (http://stackoverflow.com/help/mcve) -->
I've create a repo to demonstrate the bug: https://github.com/clarmso/firebase-serve-bug. The repo contains some modified code from examples to demonstrate the bug.

### [REQUIRED] Steps to reproduce

<!-- Provide the steps needed to reproduce the issue with the above test case. -->

1. Create a firebase project ("firebase-serve-bug") for hosting.
2. Create new project on Google Cloud Platform ("firebase-serve-bug").
3. Clone the repo.
4. cd to `rest-api/`. Enable Cloud Run API, install gcloud beta, containerize the app and deploy the container (See steps 2-3 from https://firebase.google.com/docs/hosting/cloud-run).
5. cd to `ui/`. Run `npm i`.
6. Run `firebase init`. Make sure to select the newly created firebase project in the setup. `.firebaserc` should have the correct project name.
7. Open `.firebase.json`. Ensure the routes to `/api` are rewritten to the Cloud Run service(https://github.com/clarmso/firebase-serve-bug/blob/main/ui/firebase.json#L15). (See step 4 from https://firebase.google.com/docs/hosting/cloud-run)
8. On one terminal, run `npx firebase serve --debug`.
9. On another terminal, run `curl http://localhost:5000/api/v1/hello`.

### [REQUIRED] Expected behavior

<!-- What is the expected behavior? -->
v8.18.0 or prior:

curl command is successful:
```
$ curl http://localhost:5000/api/v1/hello
Hello World!
```

Here's the relevant snippet of debug log from firebase:
```
[hosting] Cloud Run rewrite {"source":"/api/**","run":{"serviceId":"firebase-serve-bug","region":"us-central1"}} triggered
[hosting] Looking up Cloud Run service "/v1/projects/firebase-serve-bug-301205/locations/us-central1/services/firebase-serve-bug" for its URL
[2021-01-09T07:22:29.608Z] >>> HTTP REQUEST GET https://run.googleapis.com/v1/projects/firebase-serve-bug-301205/locations/us-central1/services/firebase-serve-bug

[2021-01-09T07:22:29.913Z] <<< HTTP RESPONSE 200 {"content-type":"application/json; charset=UTF-8","vary":"X-Origin, Referer, Origin,Accept-Encoding","date":"Sat, 09 Jan 2021 07:22:29 GMT","server":"ESF","cache-control":"private","x-xss-protection":"0","x-frame-options":"SAMEORIGIN","x-content-type-options":"nosniff","alt-svc":"h3-29=\":443\"; ma=2592000,h3-T051=\":443\"; ma=2592000,h3-Q050=\":443\"; ma=2592000,h3-Q046=\":443\"; ma=2592000,h3-Q043=\":443\"; ma=2592000,quic=\":443\"; ma=2592000; v=\"46,43\"","accept-ranges":"none","transfer-encoding":"chunked"}
[hosting] Rewriting /api/v1/hello to https://firebase-serve-bug-jg4ma3c3za-uc.a.run.app for Cloud Run service "firebase-serve-bug" for region "us-central1"
[2021-01-09T07:22:29.916Z] >>> [apiv2][query] GET https://firebase-serve-bug-jg4ma3c3za-uc.a.run.app/api/v1/hello
[2021-01-09T07:22:31.150Z] <<< [apiv2][status] GET https://firebase-serve-bug-jg4ma3c3za-uc.a.run.app/api/v1/hello 200
[2021-01-09T07:22:31.150Z] <<< [apiv2][body] GET https://firebase-serve-bug-jg4ma3c3za-uc.a.run.app/api/v1/hello [stream]
i  hosting: 127.0.0.1 - - [09/Jan/2021:07:22:31 +0000] "GET /api/v1/hello HTTP/1.1" 200 13 "-" "curl/7.64.1" {"metadata":{"emulator":{"name":"hosting"},"message":"127.0.0.1 - - [09/Jan/2021:07:22:31 +0000] \"GET /api/v1/hello HTTP/1.1\" 200 13 \"-\" \"curl/7.64.1\""}}
```

### [REQUIRED] Actual behavior

<!-- Run the command with --debug flag, and include the logs below. -->

curl command failed:
```
$ curl http://localhost:5000/api/v1/hello
An internal error occurred while proxying for Cloud Run service "firebase-serve-bug" for region "us-central1"
```

Here's the relevant snippet of debug log from firebase serve. Note the HTTP 500:
```
[hosting] Cloud Run rewrite {"source":"/api/**","run":{"serviceId":"firebase-serve-bug","region":"us-central1"}} triggered
[hosting] Looking up Cloud Run service "/v1/projects/firebase-serve-bug-301205/locations/us-central1/services/firebase-serve-bug" for its URL
[2021-01-09T07:20:48.695Z] >>> HTTP REQUEST GET https://run.googleapis.com/v1/projects/firebase-serve-bug-301205/locations/us-central1/services/firebase-serve-bug

[2021-01-09T07:20:49.121Z] <<< HTTP RESPONSE 200 {"content-type":"application/json; charset=UTF-8","vary":"X-Origin, Referer, Origin,Accept-Encoding","date":"Sat, 09 Jan 2021 07:20:49 GMT","server":"ESF","cache-control":"private","x-xss-protection":"0","x-frame-options":"SAMEORIGIN","x-content-type-options":"nosniff","alt-svc":"h3-29=\":443\"; ma=2592000,h3-T051=\":443\"; ma=2592000,h3-Q050=\":443\"; ma=2592000,h3-Q046=\":443\"; ma=2592000,h3-Q043=\":443\"; ma=2592000,quic=\":443\"; ma=2592000; v=\"46,43\"","accept-ranges":"none","transfer-encoding":"chunked"}
[hosting] Rewriting /api/v1/hello to https://firebase-serve-bug-jg4ma3c3za-uc.a.run.app for Cloud Run service "firebase-serve-bug" for region "us-central1"
[2021-01-09T07:20:49.125Z] >>> [apiv2][query] GET https://firebase-serve-bug-jg4ma3c3za-uc.a.run.app/api/v1/hello
i  hosting: 127.0.0.1 - - [09/Jan/2021:07:20:49 +0000] "GET /api/v1/hello HTTP/1.1" 500 - "-" "curl/7.64.1" {"metadata":{"emulator":{"name":"hosting"},"message":"127.0.0.1 - - [09/Jan/2021:07:20:49 +0000] \"GET /api/v1/hello HTTP/1.1\" 500 - \"-\" \"curl/7.64.1\""}}
```
