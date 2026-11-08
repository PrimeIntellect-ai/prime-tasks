NPE in fixing of LineLength Rule
## Describe the bug
If LineLength Rule is fixing annotation length, then NPE happens

## Invalid line
```kotlin
 @Query(value = "select * from test inner join test_execution on test.id = test_execution.test_id and test_execution.status = 'READY' and test_execution.test_suite_execution_id = ?3 limit ?1 offset ?2", nativeQuery = true)
 fun retrieveBatches(limit: Int, offset: Int, executionId: Long): List<Test>
```
## Stack trace
```
[ERROR] 2021-04-23 15:57:41 Internal error has occurred in line-length. Please make an issue on this bug at https://github.com/cqfn/diKTat/.
java.lang.NullPointerException
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.fixError(LineLength.kt:192)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.access$fixError(LineLength.kt:59)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength$checkLength$1$1.invoke(LineLength.kt:92)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength$checkLength$1$1.invoke(LineLength.kt:91)
	at org.cqfn.diktat.ruleset.constants.Warnings.warnAndFix(Warnings.kt:255)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.checkLength(LineLength.kt:89)
	at org.cqfn.diktat.ruleset.rules.chapter3.LineLength.logic(LineLength.kt:73)
	at org.cqfn.diktat.ruleset.rules.DiktatRule.visit(DiktatRule.kt:45)
	at com.pinterest.ktlint.core.KtLint$format$1.invoke(KtLint.kt:271)
	at com.pinterest.ktlint.core.KtLint$format$1.invoke(KtLint.kt:23)
	at com.pinterest.ktlint.core.KtLint$visitor$2$2.invoke(KtLint.kt:212)
	at com.pinterest.ktlint.core.KtLint$visitor$2$2.invoke(KtLint.kt:23)
	at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:224)
	at com.pinterest.ktlint.core.KtLint$visitor$2.invoke(KtLint.kt:211)
	at com.pinterest.ktlint.core.KtLint$visitor$2.invoke(KtLint.kt:23)
	at com.pinterest.ktlint.core.KtLint.format(KtLint.kt:264)
	at com.pinterest.ktlint.internal.FileUtilsKt.formatFile(FileUtils.kt:79)
	at com.pinterest.ktlint.KtlintCommandLine.process(Main.kt:331)
	at com.pinterest.ktlint.KtlintCommandLine.access$process(Main.kt:116)
	at com.pinterest.ktlint.KtlintCommandLine$lintFiles$2$1.call(Main.kt:257)
	at com.pinterest.ktlint.KtlintCommandLine$lintFiles$2$1.call(Main.kt:116)
	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
	at java.base/java.lang.Thread.run(Thread.java:834)
```

## Environment information
* build tool (maven/gradle): gradle
* how is diktat run (CLI, plugin, etc.): plugin
* kotlin version: 1.4.32

### Additional contract requirements

When auto-fixing an overlong annotation, the fixer must complete without throwing a `NullPointerException` and must shorten or split the annotation so that its resulting lines do not exceed the configured line-length limit. If the fix splits a string literal in the annotation, the literal's content must be preserved.
