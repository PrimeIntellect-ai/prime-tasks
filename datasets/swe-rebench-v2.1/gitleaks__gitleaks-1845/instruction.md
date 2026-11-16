Rule-specific allowlist paths not working with extend useDefault = true
## Gitleaks Issue Report

**Describe the bug**
Rule-specific allowlist `paths` configuration does not seem to be applied or evaluated when extending the default configuration using `[extend] useDefault = true`. Findings within the specified path are still reported by the targeted rule, contrary to expectations.

**To Reproduce**
Steps to reproduce the behavior:

1. Create a `.gitleaks.toml` file with the following content:

    ```toml
    [extend]
    useDefault = true

    [[rules]]
      id = "generic-api-key"
      [[rules.allowlists]]
        description = "Exclude a specific file from generic-api-key rule"
        paths = [
          '''^path/to/your/problematic/file\.js$'''
        ]
    ```

2. Ensure a file exists at the path `path/to/your/problematic/file.js` (relative to the execution directory) containing content that triggers the `generic-api-key` rule (e.g., a false positive like `.keys,b=a.length-1;`).
3. Run the command: `gitleaks dir -v -c .gitleaks.toml -l debug`

**Expected behavior**
The file `path/to/your/problematic/file.js` should **not** be reported as a finding by the `generic-api-key` rule. The debug log should ideally show evidence that the rule-specific `paths` allowlist was evaluated and matched for this file and rule.

**Screenshots**
N/A. Debug logs provide the necessary evidence.

**Basic Info (please complete the following information):**

* OS: **macOS Sequoia 15.4.1**
* Gitleaks Version: v8.25.0

**Additional context**

* The primary goal is to use rule-specific `paths` allowlisting as described in the documentation, not global allowlists or `.gitleaksignore`.
* The configuration method (extending defaults and adding `[[rules.allowlists]]` with `paths` to a specific rule ID) appears consistent with the Gitleaks documentation examples.
* Debug logs (`-l debug`) clearly show that:
  * The configuration file is loaded.
  * Default config extension occurs.
  * **Global** allowlist paths (`[[allowlists]]`) are correctly evaluated and skip files.
  * **However, there is no log entry indicating the evaluation or application of the rule-specific `paths` allowlist** (`^path/to/your/problematic/file\.js$`) for the `generic-api-key` rule.
* The finding for the specified file and rule (`generic-api-key`) is still present in the final output.
* This discrepancy suggests a potential issue (bug or undocumented limitation) in how Gitleaks v8.25.0 handles the merging or application of rule-specific `paths` allowlists when `[extend] useDefault = true` is active.

cc @zricethezav
