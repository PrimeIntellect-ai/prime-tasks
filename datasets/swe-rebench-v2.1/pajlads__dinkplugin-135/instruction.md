Option to let the Loot notifier ignore Clue drops?
It would be nice to prevent duplicate clue notifications. They way I did it on UniversalDiscordPlugin: https://github.com/TomBolks/UniversalDiscordNotifier/commit/6da978c1f7ba73afc44999134577f109df5f7c73#diff-ddb861fd31a9f9e62e73b89e9b9a6d24439ff3a173130e6829c997f9a016b121R46
Always ignoring all loot from clue's.

But now I think a checkbox in the config would be a bit nicer.

![image](https://user-images.githubusercontent.com/17124771/213288962-1881e624-bb3b-4b61-b0d7-4b0b8af5a8c4.png)

### Additional contract requirements

- The configuration interface `dinkplugin.DinkPluginConfig` must expose a user-selectable option named `lootIncludeClueScrolls` that returns a `boolean` and controls whether loot obtained from clue scrolls is included in loot notifications.
