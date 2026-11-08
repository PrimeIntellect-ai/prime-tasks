Death: 3 item icons posted on Death while no option to enable or disable this
**Dink version:** 1.1.2
When posting a death, 3 icons of certain items are posted below the screenshot, this also happens when the screenshot feature is off.

![Dink deaths 3 icons](https://user-images.githubusercontent.com/11279045/206911931-c77c5284-f480-45b2-957e-b6729748165d.png)

There's no option on the Deaths section to disable or enable this.

### Additional contract requirements

- The item icons attached to a death notification are the icons of the protected (kept) items, with one embed per kept item.
- `dinkplugin.DinkPluginConfig` exposes a no-argument boolean option `deathEmbedKeptItems()` that controls whether those protected-item embeds are included.
- When `deathEmbedKeptItems()` is `true`, the protected-item embeds are included in the death notification; when it is `false`, no protected-item embeds are included.
