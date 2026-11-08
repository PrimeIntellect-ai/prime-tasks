Report generation fails if scenario name contains non allowed characters
About The Problem
---
If the scenario name contains characters that are invalid for a file name (e.g. `/` on windows/linux, or `:` on windows), the report generation fails to produce the report of this scenario.

**To reproduce:**
- Clean-up the target folder
- Edit a scenario file an set a `/` in the name (e.g. `integration_test_files/helloworld/get_api_integration_test.json`)
- Run the test for this scenario: `mvn test -ntp -pl core -Dtest=**/HelloWorldInMemoryTest`

**Expected:** Report generation succeeds, see e.g. this action run: https://github.com/javiertuya/zerocode/actions/runs/11425689187

**Actual:** Report generation fails, see e.g. this action run: https://github.com/javiertuya/zerocode/actions/runs/11425675217. Report generation displays this message:
```
2024-10-20 10:45:40,538 [main] INFO org.jsmart.zerocode.core.engine.listener.TestUtilityListener - Generating test-statistics reports. please wait...
2024-10-20 10:45:40,539 [main] ERROR org.jsmart.zerocode.core.report.ZeroCodeReportGeneratorImpl -
			************
Now files were found in folder:target/zerocode-test-reports/, hence could not proceed.
(If this was intentional, then you can safely ignore this error)
			**************
```
Implemented Solution
---
[HIDDEN] More details are in the PR below.
Please go to the "Motivation & Context" section in [this](https://github.com/authorjapps/zerocode/pull/692#issue-2614300875) PR.

### Additional contract requirements

When a scenario name contains characters invalid in a filename, generating its JSON report must succeed. The report filename keeps ASCII letters, digits, spaces, hyphens, underscores, and periods; every other character is replaced with an underscore.
