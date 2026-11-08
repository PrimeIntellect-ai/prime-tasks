Apply an empty `com.github.johnrengelman.shadow` plugin to simplfy migration to the new plugin id `com.gradleup.shadow`
### What feature do you want to see added?

With the rename of this plugin, existing build logic that reacts to the application of the `com.github.johnrengelman.shadow` plugin will no longer be executed.

If this plugin was applying an empty plugin with this plugin id, the logic would still be executed since currently `com.gradleup.shadow` is a drop-in replacement for the previous plugin.

The main downside of doing this is that there is no clear path to deprecate and finally remove that behaviour while warning users that may rely on it without realising it as Gradle does not have APIs for this.

### Upstream changes

Gradle will be releasing a version of the `plugin-publish` plugin that accounts for this new plugin id because without it, some plugin publishing opinions are not enforced when applying `shadow`.

### Are you interested in contributing this feature?

If there is agreement to do this, I would be willing to submit a patch for it.
