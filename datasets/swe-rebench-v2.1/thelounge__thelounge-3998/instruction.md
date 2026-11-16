highlights also needs an exclude list
Currently it is impossible to silence specific notifications that include your nick because there are no negative-highlight-matches.

We need a list of words to be excluded from notifications that passed the current include list, so we remove the false positives.

Imagine that you have bots that may notify about build status or commit messages made by yourself, and you are high-likely to not want to be notified about your own actions.

### Additional contract requirements

- Store the exclusion list in `clientSettings.highlightExceptions` and expose its compiled matcher as `client.highlightExceptionRegex`.
- Users must be able to configure the exclusion list through the existing settings interface.
- When an incoming message would otherwise be highlighted (because it matches the user's nickname or the custom highlights), but its IRC-formatting-stripped text matches the exclusion list, the message must not be highlighted: `msg.highlight` must be `false`, so no notification is sent for it.
