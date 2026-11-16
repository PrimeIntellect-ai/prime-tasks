Detox retry of failed tests is not working when a single test fail
### Did you test using the latest Detox?

- [x] I have tested this issue on the latest Detox release and it still reproduces.

### Did your test fail and you're not sure why?

- [x] I have read the troubleshooting guide and it didn't help me.

### What happened?

1.  Run detox with retry
2. Make only one test fail
Result => retry will not work

Looks like jest is not working well with shard option and single file.
Removing shard option from the command line works.

### In what environment did this happen?

Detox version: 20.37.0
React Native version:
Has Fabric (React Native's new rendering system) enabled: (yes/no)
Node version:
Test-runner (select one): jest / other


Detox logs:


11:54:45.875 detox[29382] i There were failing tests in the following files:
--
  | 1. detox/admin/hiddenCollapsed.test.js
  |
  | Detox CLI is going to restart the test runner with those files...
  |
  | 11:54:45.876 detox[29382] B jest --forceExit --no-color --ci --shard 2/2 /Users/builder/uibuilder/work/detox/admin/hiddenCollapsed.test.js
  | No tests found, exiting with code 1
  | Run with `--passWithNoTests` to exit with code 0
  | In /Users/builder/uibuilder/work
  | 103 files checked.
  | testMatch: /Users/builder/uibuilder/work/detox/admin/backendFunctions.test.js, /Users/builder/uibuilder/work/detox/admin/hiddenCollapsed.test.js, /Users/builder/uibuilder/work/detox/admin/layout.test.js, /Users/builder/uibuilder/work/detox/admin/mobuiButton.test.js, /Users/builder/uibuilder/work/detox/admin/mobuiImage.test.js, /Users/builder/uibuilder/work/detox/admin/mobuiPicker.test.js, /Users/builder/uibuilder/work/detox/admin/mobuiSwitch.test.js, /Users/builder/uibuilder/work/detox/admin/mobuiText.test.js, /Users/builder/uibuilder/work/detox/admin/mobuiTextInput.test.js, /Users/builder/uibuilder/work/detox/admin/showInAppNotification.test.js, /Users/builder/uibuilder/work/detox/admin/showToastNotification.test.js, /Users/builder/uibuilder/work/detox/admin/storage.test.js, /Users/builder/uibuilder/work/detox/admin/showActionSheet.test.js, /Users/builder/uibuilder/work/detox/admin/widgetViewerScreen.test.js, /Users/builder/uibuilder/work/detox/admin/widgetViewerSectionScreen.test.js - 15 matches
  | testPathIgnorePatterns: /node_modules/ - 103 matches
  | testRegex:  - 0 matches
  | Pattern: /Users/builder/uibuilder/work/detox/admin/hiddenCollapsed.test.js - 0 matches
