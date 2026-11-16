default PARAM isn't being injected during extension emulation
<!-- DO NOT DELETE
validate_template=true
template_path=.github/ISSUE_TEMPLATE/bug_report.md
-->

### [REQUIRED] Environment info

**firebase-tools:**
8.17.0

**Platform:**
macOS Catalina 10.15.4

### [REQUIRED] Test case

See steps to reproduce.

### [REQUIRED] Steps to reproduce

1. git clone `git@github.com:firebase/extensions.git`
2. run `npm i` from root of extension's directory.
3. cd `delete-user-data` directory
4. create `test-params.env` file. Add environment variables & insert project id as appropriate:
```env
LOCATION=europe-west2
STORAGE_PATHS={DEFAULT}/test/{UID}-test.png
SELECTED_DATABASE_INSTANCE=[INSERT YOUR OWN PROJECT ID]
FIRESTORE_DELETE_MODE=shallow
```
5. run CLI command with your project id: `firebase ext:dev:emulators:start --test-params=test-params.env --project=[INSERT YOUR OWN PROJECT ID]`

### [REQUIRED] Expected behavior

The auth emulator and the cloud function emulator running.

### [REQUIRED] Actual behavior

The emulator command is erroring because the `${DATABASE_INSTANCE}'` param which is auto populated in the `extensions.yaml` during build time, is not being recognised by the emulator.
```
Error: The extension.yaml has the following errors:
  - Param SELECTED_DATABASE_INSTANCE has default value '${DATABASE_INSTANCE}', which does not pass the validationRegex ^([0-9a-z_.-]*)$
```

I did also try `${param:DATABASE_INSTANCE}` in the `extension.yaml` but I got the same error:

```
Error: The extension.yaml has the following errors:
  - Param SELECTED_DATABASE_INSTANCE has default value '${param:DATABASE_INSTANCE}', which does not pass the validationRegex ^([0-9a-z_.-]*)$
```
