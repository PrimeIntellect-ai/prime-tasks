`Entity` requires a hand-implemented `toString`, because it's part of `CodeSmell.toString`
## Steps to Reproduce
Put `findings.toString()` anywhere, e.g. test results HTML.

## Expected Behavior
`.toString()` works as before.

I think it should be considered public API and be tested.

## Observed Behavior
```
Found findings:
CodeSmell(issue=Issue(id='UptightFun'), entity=io.gitlab.arturbosch.detekt.api.Entity@5b88b8e, message=Bad code!, references=[], severity=ERROR, id='UptightFun')
CodeSmell(issue=Issue(id='UptightFun'), entity=io.gitlab.arturbosch.detekt.api.Entity@58253c57, message=Bad code!, references=[], severity=ERROR, id='UptightFun')
```
There's no way to know what that entity is without actually debugging the code, or writing a good amount of code to generate external toStrings.

## Context
This change caused the problem: https://github.com/detekt/detekt/pull/6477/files#diff-33451aa64de4e366a232a4eaa18ae7f23aa92e389ca711c85eb3bfb18734d11cR14

cc @3flex @BraisGabin

## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: `main-SNAPSHOT` (e9423cb)
* Version of Gradle used (if applicable): N/A
* Gradle scan link (add `--scan` option when running the gradle task): N/A
* Operating System and version: N/A
* Link to your project (if it's a public repository): https://github.com/TWiStErRob/net.twisterrob.detekt/pull/11/checks?check_run_id=19158201624
Example: `fails on multiple findings() (net.twisterrob.detekt.testing.VerifyTest$verifyNoFindings function) failed`
