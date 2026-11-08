hosting:channel:deploy: Hosting configs should only include either "site" or \"target\", not both.
<!-- DO NOT DELETE
validate_template=true
template_path=.github/ISSUE_TEMPLATE/bug_report.md
-->

I have a multisite config with targets. Using `npx firebase-tools deploy --only hosting` or `npx firebase-tools deploy --only hosting:bbbb` works fine. But if I use the new GitHub action, it fails on the line:

```
 /usr/local/bin/npx firebase-tools hosting:channel:deploy pr22-blah --expires 30d --project blah-dev --json
```

Running the same thing locally fails in the same way.  The error is:

```sh
$ npx firebase-tools hosting:channel:deploy pr22-blah --only bbb --expires 30d --project blah-dev --json
{
  "status": "error",
  "error": "Hosting configs should only include either \"site\" or \"target\", not both."
}
```

Note that the command I used there adds `--only bbb`. The command fails the same way with or without that.

Also note that my `firebase.json` does NOT list `"site"` at all. See below:

.firebaserc:
```json
{
  "projects": {
    "default": "blah-dev",
    "dev": "blah-dev",
    "prod": "blah-io"
  },
  "targets": {
    "blah-io": {
      "hosting": {
        "aaa": [
          "blah-aaa"
        ],
        "boilerplate": [
          "blah-boilerplate"
        ],
        "bbb": [
          "blah-bingo"
        ]
      }
    },
    "blah-dev": {
      "hosting": {
        "aaa": [
          "blah-aaa-dev"
        ],
        "boilerplate": [
          "blah-boilerplate-dev"
        ],
        "bbb": [
          "blah-bbb-dev"
        ]
      }
    }
  }
}
```

firebase.json
```json
{
  "firestore": {...},
  "database": {...},
  "functions": {...},
  "hosting": [
    {
      "target": "aaa",
      "public": "packages/aaa/build",
      "ignore": [
        "firebase.json",
        "**/.*",
        "**/node_modules/**"
      ],
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ]
    },
    {
      "target": "boilerplate",
      "public": "packages/boilerplate/build",
      "ignore": [
        "firebase.json",
        "**/.*",
        "**/node_modules/**"
      ],
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ]
    },
    {
      "target": "bbb",
      "public": "packages/bbb/build",
      "ignore": [
        "firebase.json",
        "**/.*",
        "**/node_modules/**"
      ],
      "rewrites": [
        {
          "source": "**",
          "destination": "/index.html"
        }
      ]
    }
  ],
  "emulators": {...}
}

```

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


**firebase-tools:**. `npx firebase-tools --version` -> `8.14.0`

**Platform:** OSX, but also GitHub Actions default image

### [REQUIRED] Test case

See above.

### [REQUIRED] Steps to reproduce

See above. Run the hosting:channel:deploy command

### [REQUIRED] Expected behavior

It deploys

### [REQUIRED] Actual behavior

```
{
  "status": "error",
  "error": "Hosting configs should only include either \"site\" or \"target\", not both."
}
```

(`--debug` flag adds a lot of HTTP logging noise at the front, but it's all 200s.)

### Additional contract requirements

- A public function `normalizedHostingConfigs(cmdOptions, options?)` is exported from the module `src/hosting/normalizedHostingConfigs`. It returns an array of normalized Hosting configuration objects (`HostingConfig[]`), which may be empty when no Hosting configuration is defined.
- `cmdOptions` provides `site` (the default site name), `config` (an object with a `get(key)` method returning the raw Hosting configuration), and `rc` (an object with a `requireTarget()` method returning the required target names).
- `options` may include `resolveTargets` (boolean). When it is `true`, `target` references are resolved to concrete site configurations, and the caller's original configuration object must not be modified.
- A `hosting:channel:deploy` command that uses a `target`-based Hosting configuration must not fail with the error `Hosting configs should only include either "site" or "target", not both.`
