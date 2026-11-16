Dagger factory generator breaks in modules containing `-` in name
### Current behavior

Here `app-display` is the consuming app module and `display-legacy` is the producing library module. The generated code expects class `FakeRotationModule_Companion_FakeRotation$display_legacy_debugFactory`.
```
> Task :app-display:compileDebugJavaWithJavac FAILED
C:\gradle\build\...\app-display\generated\source\kapt\debug\...DaggerHomeComponent.java:6: error: cannot find symbol
import ....FakeRotationModule_Companion_FakeRotation$display_legacy_debugFactory;
                                                         ^
  symbol:   class FakeRotationModule_Companion_FakeRotation$display_legacy_debugFactory
  location: package ...
```
The factory exists on disk with a dash; Anvil generates class `FakeRotationModule_Companion_FakeRotation$display-legacy_debugFactory`.

![image](https://user-images.githubusercontent.com/4589773/202015156-f7a9a509-38f5-45eb-a810-43e8993787e8.png)

### What's likely happening

`-` is a valid part of a Kotlin identifier so the source file is generated with a dash. Dagger would generate an underscore instead. This mismatch causes compile-time errors when attempting to generate a component from Anvil-generated `@Module`s in Gradle modules whose names contain `-`.

### Expected behavior

Anvil should use Java validation rules for class names when generating Dagger factories.

### Workarounds

* Use only valid Java identifiers as module names
* Use kapt and actual Dagger compiler
