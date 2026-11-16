Get Emote Sets missing OwnerID value
The [Get Emote Sets](https://github.com/nicklaw5/helix/blob/main/chat.go#L128) function is missing the `OwnerID` value returned [from the API](https://dev.twitch.tv/docs/api/reference#get-emote-sets).

The simple solution is to [HIDDEN], but that'd mean an empty value in the other calls using the type (i.e. Get Channel Emotes and Get Global Emotes).
The complex solution is to [HIDDEN].

I'm happy to make the change with a PR but I'd like to hear your preferred solution first.

### Additional contract requirements

- A successful Get Emote Sets response must expose the API-provided OwnerID for each returned emote.
