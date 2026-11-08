apiDump task incompatible with configuration cache
```
FAILURE: Build failed with an exception.

* What went wrong:
Configuration cache problems found in this build.

10 problems were found storing the configuration cache.
- Task `:detekt-api:apiDump` of type `org.gradle.api.tasks.Sync`: cannot serialize object of type 'kotlinx.validation.KotlinApiBuildTask', a subtype of 'org.gradle.api.Task', as these are not supported with the configuration cache.
  See https://docs.gradle.org/7.5/userguide/configuration_cache.html#config_cache:requirements:task_access
- Task `:detekt-api:apiDump` of type `org.gradle.api.tasks.Sync`: cannot serialize object of type 'org.gradle.api.internal.project.DefaultProject', a subtype of 'org.gradle.api.Project', as these are not supported with the configuration cache.
  See https://docs.gradle.org/7.5/userguide/configuration_cache.html#config_cache:requirements:disallowed_types
```
