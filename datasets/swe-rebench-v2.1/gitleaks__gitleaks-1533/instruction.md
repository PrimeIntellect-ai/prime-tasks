Gitleaks precommit staged still scans the whole git history
**Describe the bug**
Gitleaks precommit staged still scans the whole git history.
When running gitleaks in a pre-commit hook, the new options
`gitleaks git --pre-commit --staged ` scans and reports leaks on the whole git history.

**To Reproduce**
Run `gitleaks git --pre-commit --staged` in a project this, will always scan the git history and ignore the staged files.

**Expected behavior**
Running `gitleaks git --pre-commit --staged` in a project should only scan staged files, not the whole history

**Basic Info (please complete the following information):**
 - OS: Ubuntu 22.04.5 LTS
 - Gitleaks Version: 8.19.2

cc @zricethezav
