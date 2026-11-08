IDENTIFIER_NAME rule causes NPE
```
[ERROR] 2021-11-09 16:29:07 Internal error has occurred in rule [identifier-naming]. Please make an issue on this bug at https://github.com/cqfn/diKTat/.
                       As a workaround you can disable these inspections in yml config: <[BACKTICKS_PROHIBITED, VARIABLE_NAME_INCORRECT, VARIABLE_NAME_INCORRECT_FORMAT, CONSTANT_UPPERC
ASE, VARIABLE_HAS_PREFIX, CONFUSING_IDENTIFIER_NAMING, GENERIC_NAME, CLASS_NAME_INCORRECT, ENUM_VALUE, EXCEPTION_SUFFIX, FUNCTION_BOOLEAN_PREFIX, FUNCTION_NAME_INCORRECT_CASE, IDENTIFI
ER_LENGTH, OBJECT_NAME_INCORRECT, TYPEALIAS_NAME_INCORRECT_CASE]>.
                       Root cause of the problem is in [D:\reflekt\reflekt-plugin\src\main\kotlin\io\reflekt\plugin\utils\Util.kt] file.
java.lang.NullPointerException
        at org.cqfn.diktat.ruleset.rules.chapter1.IdentifierNaming$checkVariableName$1$2.invoke(IdentifierNaming.kt:219)
        at org.cqfn.diktat.ruleset.rules.chapter1.IdentifierNaming$checkVariableName$1$2.invoke(IdentifierNaming.kt:205)
        at org.cqfn.diktat.ruleset.constants.Warnings.warnAndFix(Warnings.kt:260)
        at org.cqfn.diktat.ruleset.constants.Warnings.warnAndFix$default(Warnings.kt:202)
        at org.cqfn.diktat.ruleset.rules.chapter1.IdentifierNaming.checkVariableName(IdentifierNaming.kt:205)
        at org.cqfn.diktat.ruleset.rules.chapter1.IdentifierNaming.logic(IdentifierNaming.kt:128)
        at org.cqfn.diktat.ruleset.rules.DiktatRule.visit(DiktatRule.kt:50)
        at com.pinterest.ktlint.core.KtLint$format$1.invoke(KtLint.kt:381)

```

Small reproducer:

```
package io.reflekt.plugin.utils

object Util {
    private val GET_USES: String
}

```

### Additional contract requirements

- When fixing the supplied reproducer, the rule must rename `GET_USES` to `getUses`.
