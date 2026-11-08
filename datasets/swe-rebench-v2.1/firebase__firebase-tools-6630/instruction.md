Custom dotEnv parser doesn't support `export` prefix
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

**firebase-tools:** 13.0.1

**Platform:** macOS

### [REQUIRED] Test case

```
firebase init hosting
echo 'export X=y' > ./hosting/.env.test
firebase deploy
```

### [REQUIRED] Steps to reproduce

Create a firebase project with Next.js hosting. Use `export` in `.env`, then try to deploy via `firebase deploy`.

It's not totally clear to me if having a "test" alias for the firebase project is relevant to `.env.test` getting picked up, but I'll mention it in case it is.

### [REQUIRED] Expected behavior

Firebase successfully deploys, either ignoring `.env.test`, or at least parsing it without crashing.

### [REQUIRED] Actual behavior

Firebase complains that `export` is not valid syntax, which is incorrect. Basically [every](https://github.com/bkeepers/dotenv#usage) [other](https://hexdocs.pm/dotenvy/dotenv-file-format.html) [dotenv](https://github.com/theskumar/python-dotenv/blob/3ffcef60d10813b72ecf85d5941d51b0207cd40e/src/dotenv/parser.py#L14) [parser](https://github.com/joho/godotenv/blob/e3b6eee84d15b0fa274078565ca46591f5e08876/parser.go#L17) [implementation](https://github.com/vlucas/phpdotenv/blob/334f4952967f3ee6cdb2004e05e0bd01b525d56b/src/Parser/EntryParser.php#L88-L89) supports each line being prefixed by the word `export`, which allows users to source that file in their shell of choice without modification during local testing.

Actual output looks like this:

```
=== Deploying to 'my-project-4867'...

i  deploying functions, hosting
i  functions: preparing codebase firebase-frameworks-my-project-4867 for deployment
i  functions: ensuring required API cloudfunctions.googleapis.com is enabled...
i  functions: ensuring required API cloudbuild.googleapis.com is enabled...
i  artifactregistry: ensuring required API artifactregistry.googleapis.com is enabled...
✔  functions: required API cloudbuild.googleapis.com is enabled
✔  functions: required API cloudfunctions.googleapis.com is enabled
✔  artifactregistry: required API artifactregistry.googleapis.com is enabled
i  functions: Loading and analyzing source code for codebase firebase-frameworks-my-project-4867 to determine what to deploy
Serving at port 8221

Error: Failed to load environment variables from .env.test.:
- FirebaseError Invalid dotenv file, error on lines: export X=y
```

Link to relevant parser code: https://github.com/firebase/firebase-tools/blob/master/src/functions/env.ts#L114-L149
