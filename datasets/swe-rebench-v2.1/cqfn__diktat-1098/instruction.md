Null pointer exception at: GENERIC_VARIABLE_WRONG_DECLARATION
```
package io.reflekt.plugin.scripting

import io.reflekt.plugin.analysis.models.Import
import java.io.File
import kotlin.reflect.KClass
import kotlin.script.experimental.api.*
import kotlin.script.experimental.host.toScriptSource
import kotlin.script.experimental.jvm.jvm
import kotlin.script.experimental.jvm.updateClasspath
import kotlin.script.experimental.jvmhost.BasicJvmScriptingHost

class KotlinScript(
    code: String,
    imports: List<Import> = emptyList(),
    properties: List<Pair<String, KClass<*>>> = emptyList(),
    classpath: List<File> = emptyList()
) {
    private val argumentNames = properties.map { it.first }
    private val source = (imports.joinToString(separator = System.lineSeparator(), postfix = System.lineSeparator()) { it.text } + code).toScriptSource()
    private val compilationConfiguration = ScriptCompilationConfiguration {
        jvm {
            updateClasspath(classpath)
        }
        providedProperties(*properties.toTypedArray())
    }

    fun eval(arguments: List<*> = emptyList<Any>()): Any? =
        (execute(arguments).value.returnValue as ResultValue.Value).value

    fun run(arguments: List<*> = emptyList<Any>()) {
        execute(arguments)
    }

    private fun execute(arguments: List<*>): ResultWithDiagnostics.Success<EvaluationResult> {
        val evaluationConfiguration = ScriptEvaluationConfiguration {
            providedProperties(*argumentNames.zip(arguments).toTypedArray())
        }
        val result = BasicJvmScriptingHost().eval(
            source, compilationConfiguration, evaluationConfiguration
        )
        if (result !is ResultWithDiagnostics.Success) {
            throw RuntimeException("Failed to evaluate script:\n${result.reports.map { it.render(withStackTrace = true)} }}")
        }
        return result
    }
}
```

Null pointer exception is thrown:
```
[ERROR] 2021-11-07 13:04:25 Internal error has occurred in rule [variable-generic-type]. Please make an issue on this bug at https://github.com/cqfn/diKTat/.
                       As a workaround you can disable these inspections in yml config: <[GENERIC_VARIABLE_WRONG_DECLARATION]>.
                       Root cause of the problem is in [/mnt/d/reflekt/reflekt-plugin/src/main/kotlin/io/reflekt/plugin/scripting/KotlinScript.kt] file.
java.lang.NullPointerException
        at org.cqfn.diktat.ruleset.rules.chapter4.VariableGenericTypeDeclarationRule.handleProperty(VariableGenericTypeDeclarationRule.kt:59)
        at org.cqfn.diktat.ruleset.rules.chapter4.VariableGenericTypeDeclarationRule.logic(VariableGenericTypeDeclarationRule.kt:30)
        at org.cqfn.diktat.ruleset.rules.DiktatRule.visit(DiktatRule.kt:50)
        at com.pinterest.ktlint.core.KtLint$lint$1.invoke(KtLint.kt:81)
        at com.pinterest.ktlint.core.KtLint$lint$1.invoke(KtLint.kt:23)
        at com.pinterest.ktlint.core.KtLint$visitor$2$1.invoke(KtLint.kt:206)
        at com.pinterest.ktlint.core.KtLint$visitor$2$1.invoke(KtLint.kt:23)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:224)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.ast.PackageKt.visit(package.kt:225)
        at com.pinterest.ktlint.core.KtLint$visitor$2.invoke(KtLint.kt:204)
        at com.pinterest.ktlint.core.KtLint$visitor$2.invoke(KtLint.kt:23)
        at com.pinterest.ktlint.core.KtLint.lint(KtLint.kt:74)
        at com.pinterest.ktlint.internal.FileUtilsKt.lintFile(FileUtils.kt:51)
        at com.pinterest.ktlint.KtlintCommandLine.process(Main.kt:358)
        at com.pinterest.ktlint.KtlintCommandLine.access$process(Main.kt:116)
        at com.pinterest.ktlint.KtlintCommandLine$lintFiles$2$1.call(Main.kt:257)
        at com.pinterest.ktlint.KtlintCommandLine$lintFiles$2$1.call(Main.kt:116)
        at java.util.concurrent.FutureTask.run(FutureTask.java:266)
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
        at java.lang.Thread.run(Thread.java:748)
Exception in thread "main" java.util.concurrent.ExecutionException: java.lang.Error: Internal error in diktat application
```
