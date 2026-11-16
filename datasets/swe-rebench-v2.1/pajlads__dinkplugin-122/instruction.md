Setting to skip virtual levels
I would like a setting to disable notifications for virtual levels (i.e. I only want notifications for levels 1-99).
This should probably be a simple checkbox, where the default value should

Discussion points:
Should it be a positive checkbox? "Notify for virtual levels" where true would be default
Should it be a negative checkbox? "Skip virtual levels" where false would be default

### Additional contract requirements

- The setting is a boolean configuration item named `levelNotifyVirtual` on the `DinkPluginConfig` interface (package `dinkplugin`), registered with RuneLite's `net.runelite.client.config.ConfigItem` annotation so that users can change it in the plugin's settings.
- When the setting is disabled, notifications for levels above 99 are suppressed, while notifications for levels 1-99 are still sent.
