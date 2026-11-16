Suppress/OptIn Lint warnings/errors are not ignored in Anvil/src-gen
We have some `@OptIn` Errors/Warnings.  We add to certain classes to make sure Engineers are aware of the fallout from using certain classes, however the Kotlin Compiler will flag/fail on these classes when the anvil/src-gen is compiled.

Not sure the best approach, but I'm guessing either Anvil add's the Suppression/OptIn, or has a compiler flag set to ignore lint warnings? Looks like Dagger/KSP/KAPT might ignore these as they don't warn/fail on these lint checks.

(If theres already a plugin option appologies!)
