Upper case functions not compiling
Having upper case factory-style function names cause compilation errors.
I created a quick example here:
https://github.com/PaulWoitaschek/anvil/commit/1d443c1724314f5999ed5acdcec8739cb192a875

The stacktrace is as follows:
```console
➜  anvil git:(anvil_name_hickup) ./gradlew sample:library:assemble
Watching the file system is an incubating feature.
Received 15 file system events since last build
Virtual file system retained information about 5291 files, 1326 directories and 38 missing files since last build
Configuration on demand is an incubating feature.

> Configure project :
Versions: [Kotlin:1.3.72, Gradle:6.6.1, Kotlin use IR:false, Kotlin IR supported:false]

> Task :sample:library:compileKotlin FAILED
e: /home/paul/repos/anvil/sample/library/build/anvil/src-gen-compileKotlin/com/squareup/anvil/sample/hello/HelloModule_UserFactory.kt: (10, 49): Unresolved reference: User
e: /home/paul/repos/anvil/sample/library/build/anvil/src-gen-compileKotlin/com/squareup/anvil/sample/hello/HelloModule_UserFactory.kt: (11, 32): Unresolved reference: User
e: /home/paul/repos/anvil/sample/library/build/anvil/src-gen-compileKotlin/com/squareup/anvil/sample/hello/HelloModule_UserFactory.kt: (17, 22): Unresolved reference: User

FAILURE: Build failed with an exception.

* What went wrong:
Execution failed for task ':sample:library:compileKotlin'.
> A failure occurred while executing org.jetbrains.kotlin.compilerRunner.GradleKotlinCompilerWork
   > Compilation error. See log for more details

* Try:
Run with --stacktrace option to get the stack trace. Run with --info or --debug option to get more log output. Run with --scan to get full insights.

* Get more help at https://help.gradle.org

Deprecated Gradle features were used in this build, making it incompatible with Gradle 7.0.
Use '--warning-mode all' to show the individual deprecation warnings.
See https://docs.gradle.org/6.6.1/userguide/command_line_interface.html#sec:command_line_warnings

BUILD FAILED in 733ms
14 actionable tasks: 1 executed, 13 up-to-date
Received 2 file system events for current build
Virtual file system retains information about 5294 files, 1334 directories and 38 missing files till next build
```
