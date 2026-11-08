Support for Robo Tests without Robo script
This is an enhancement request to support robo tests without a robo script.  Firebase Test Lab supports this, although it appears fladle does not. In the fladle source, the decision to do a robo test is based on the roboscript file path being non-null.

Issues sometimes come up with R8, ProGuard, or DexGuard that make robo testing the my release APK helpful in catching issues that might occur during first launch.  However, DexGuard also obfuscates resource IDs which makes creating a roboscript for a release build much more difficult.

Being able to launch a robo test without a roboscript will enable my use case, but would also lower the barrier for others who want to run a robo test without recording a script.

### Additional contract requirements

- The fladle configuration and every named configuration expose a boolean property `sanityRobo` (default `false`). Setting it to `true` marks that configuration as a sanity-Robo run.
- The fladle configuration and every named configuration expose string properties `debugApk` and `instrumentationApk`. Both accept wildcard characters in their values. `debugApk` supplies the `app` value and `instrumentationApk` supplies the `test` value of the generated gcloud YAML.
- A named configuration exposes a method `clearPropertiesForSanityRobo()` that sets `sanityRobo` to `true` and clears `instrumentationApk` and `additionalTestApks` on that same configuration.
- For a configuration whose `sanityRobo` is `true`, the generated gcloud YAML omits `test`, `robo-script`, `robo-directives` and `additional-app-test-apks`.
- A configuration whose `sanityRobo` is `true` and that also sets `roboDirectives`, `roboScript`, `instrumentationApk` or `additionalTestApks` fails the build with an error message containing:
  - for the base configuration: `Incorrect [base] configuration. [<option>] can't be used together with sanityRobo.`, where `<option>` is the offending option name (`roboDirectives`, `roboScript`, `instrumentationApk` or `additionalTestApks`);
  - for a named configuration that sets `roboScript`: `Incorrect [<name>] configuration. [roboScript] can't be used together with sanityRobo. If you want to launch robo test run without robo script place only clearPropertiesForSanityRobo() into [<name>] configuration`.
