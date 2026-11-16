[Feature] Introduce extra substitute variable(s) for Collection Log notifier
### Checklist

- [X] I've searched the [issues and pull requests](https://github.com/pajlads/Dinkplugin/issues?q=) for similar looking suggestions.
- [X] I've checked the `Unreleased` section of the [changelog](https://github.com/pajlads/DinkPlugin/blob/master/CHANGELOG.md) for newly added features that sound like my suggestion.

### Describe your Suggestion

I'd wanna have an ability to add a substitute variable to Dink for amount of collection logs a player has gotten to the notifier. For example, say I'd be called `LOGS_AMOUNT` and so using `%LOGS_AMOUNT%` inside the notifier message would be simply substituted with `592` in this scenario below:
![in-game interface showing amount of clogs gotten and total amount](https://cdn.zneix.eu/Ra4IhkP.png)

Also, introducing an another variable for the total amount is perhaps not needed, but if user were to hardcode the amount of collection logs (for example, to made their message look like what's available in the in-game inferface) available then every once in a while, when new items are added to the game & collection log, it'd be a silly thing to update, which I could also see it tedious to keep having users have to "upkeep" that.

Names for variables are up for discussion though - don't get hung up on my original suggestion with `LOGS_AMOUNT`; I think it's not good, especially with how ambiguous it could get, especially if there was the second one added too, as described in paragraph above.

### Reasoning

Friend of mine has reached out saying they were looking for a way to include the amount of collection logs, similar to how it's presented in the in-game interface, in the posted messaged, I do think it'd be nice, albeit niche, addition for whoever wants to personalize their messages.

### Additional contract requirements

- The collection-log notifier message supports the substitute variable `%COMPLETED%`, which is replaced with the number of unique collection-log entries the player has completed (the count includes the entry that triggered the notification).
- The collection-log notifier message supports the substitute variable `%TOTAL_POSSIBLE%`, which is replaced with the total number of unique collection-log entries tracked, falling back to `CollectionNotifier.TOTAL_ENTRIES` when the game varp `TOTAL_VARP` is not populated.
