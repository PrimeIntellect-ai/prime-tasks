Missing mergers: no-caller, no-eval
### 🐛 Bug Report

-   `tslint-to-eslint-config` version: dunno. used npx to run
-   ESLint version: 5.16.0
-   Node version: 8.16.0

#### Actual Behavior

my eslint config is not updated

**console output**
✨ 101 rules replaced with their ESLint equivalents. ✨
📢 4 ESLint rules behave differently from their TSLint counterparts: 📢
* no-invalid-this:
  - Functions in methods will no longer be ignored.
* one-var:
  - Variables declared in for loops will no longer be checked.
* no-plusplus:
  - ++ and -- operators will now only be allowed in for loops.
* class-methods-use-this:
  - allow-protected methods will no longer be ignored.
💀 2 errors thrown. 💀
Check ./tslint-to-eslint-config.log for details.
️👀 132 rules do not yet have ESLint equivalents; defaulting to eslint-plugin-tslint. 👀
✅ All is well! ✅

**log file**
no-eval threw an error during conversion: Error: No merger for multiple output no-eval rule configurations.
    at exports.convertRules (...\npm-cache\_npx\14132\node_modules\tslint-to-eslint-config\src\rules\convertRules.js:37:67)
    at exports.convertConfig (...\npm-cache\_npx\14132\node_modules\tslint-to-eslint-config\src\conversion\convertConfig.js:15:48)
    at <anonymous>
    at process._tickCallback (internal/process/next_tick.js:189:7)
no-arg threw an error during conversion: Error: No merger for multiple output no-caller rule configurations.
    at exports.convertRules (...\npm-cache\_npx\14132\node_modules\tslint-to-eslint-config\src\rules\convertRules.js:37:67)
    at exports.convertConfig (...\npm-cache\_npx\14132\node_modules\tslint-to-eslint-config\src\conversion\convertConfig.js:15:48)
    at <anonymous>
    at process._tickCallback (internal/process/next_tick.js:189:7)

#### Expected Behavior

eslint config would be updated

#### Reproduction

Can you reply to this issue and let me know how much help you need to repro? I'd prefer not to just copy config/details from an internal repo.
