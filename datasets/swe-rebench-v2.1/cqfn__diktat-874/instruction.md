Magic number rule failure
**Diktat version: 0.5.2**

```
[ERROR] 2021-05-08 23:21:20 Internal error has occurred in magic-number. Please make an issue on this bug at https://github.com/cqfn/diKTat/.
java.lang.ClassCastException: class org.jetbrains.kotlin.psi.KtParameter cannot be cast to class org.jetbrains.kotlin.psi.KtProperty (org.jetbrains.kotlin.psi.KtParameter and org.jetbr
ains.kotlin.psi.KtProperty are in unnamed module of loader 'app')
        [HIDDEN]
        at org.cqfn.diktat.ruleset.rules.chapter3.MagicNumberRule$checkNumber$isLocalVariable$1.invoke(MagicNumberRule.kt:29)
        at com.pinterest.ktlint.core.ast.PackageKt.parent(package.kt:159)
        at com.pinterest.ktlint.core.ast.PackageKt.parent$default(package.kt:156)
        at org.cqfn.diktat.ruleset.rules.chapter3.MagicNumberRule.checkNumber(MagicNumberRule.kt:52)
        at org.cqfn.diktat.ruleset.rules.chapter3.MagicNumberRule.logic(MagicNumberRule.kt:41)
        at org.cqfn.diktat.ruleset.rules.DiktatRule.visit(DiktatRule.kt:46)
        at com.pinterest.ktlint.core.KtLint$format$1.invoke(KtLint.kt:271)
        at com.pinterest.ktlint.core.KtLint$format$1.invoke(KtLint.kt:23)
        at com.pinterest.ktlint.core.KtLint$visitor$2$2.invoke(KtLint.kt:212)
        at com.pinterest.ktlint.core.KtLint$visitor$2$2.invoke(KtLint.kt:23)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:224)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.KtLint$visitor$2.invoke(KtLint.kt:211)
        at com.pinterest.ktlint.core.KtLint$visitor$2.invoke(KtLint.kt:23)
        at com.pinterest.ktlint.core.KtLint.format(KtLint.kt:264)
        at com.pinterest.ktlint.internal.FileUtilsKt.formatFile(FileUtils.kt:79)
        at com.pinterest.ktlint.KtlintCommandLine.process(Main.kt:331)
        at com.pinterest.ktlint.KtlintCommandLine.access$process(Main.kt:116)
        at com.pinterest.ktlint.KtlintCommandLine$lintFiles$2$1.call(Main.kt:257)
        at com.pinterest.ktlint.KtlintCommandLine$lintFiles$2$1.call(Main.kt:116)
        at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
        at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1130)
        at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:630)
        at java.base/java.lang.Thread.run(Thread.java:832)
[ERROR] 2021-05-08 23:21:20 As a workaround you can disable these inspections in yml config: [MAGIC_NUMBER]
```

### Additional contract requirements

Linting a numeric literal in a Kotlin value parameter must complete without throwing an internal error.
