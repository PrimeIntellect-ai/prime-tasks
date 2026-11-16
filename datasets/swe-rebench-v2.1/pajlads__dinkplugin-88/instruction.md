Mention boss name in Boss Slayer notifications
Currently Slayer notifications for bosses don't mention boss name since it's not included in the task complete message.
![image](https://user-images.githubusercontent.com/86596679/206470379-55bfb79f-7977-4cd5-848e-86e0b6a05ea6.png)
Looking at the game chat log, game sends a message regarding the name of the Boss and maybe location if on Konar task(unconfirmed), right before the task completion text.
![image](https://user-images.githubusercontent.com/86596679/206470970-14b3bb5e-969b-4d63-9be7-d726e21ccb72.png)
Maybe support could be added for that.

### Additional contract requirements

- For boss tasks, use `<kill count> <boss name>` as the task description in both the notification content and `SlayerNotificationData` (for example, `50 Cave Kraken`, `36 Barrows brothers`, and `11 Chaos Elemental`).
