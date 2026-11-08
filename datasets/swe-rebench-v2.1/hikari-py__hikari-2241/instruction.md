Specialize InteractionCreateEvent
### Summary

Specialize `InteractionCreateEvent` into the different interaction types, similar how `MessageCreateEvent` is specialized for guilds and dms

### Why is this needed?

Nicer DX

### Ideal implementation

Provide more concrete subclasses with correct typing for `interaction`.

### Checklist

- [X] I have searched the issue tracker and have made sure it's not a duplicate. If it is a follow up of another issue, I have specified it.

### Additional contract requirements

Provide these specialized interaction-create event classes, each with the indicated type for its `interaction` attribute: `CommandInteractionCreateEvent` uses `CommandInteraction`, `ComponentInteractionCreateEvent` uses `ComponentInteraction`, `AutocompleteInteractionCreateEvent` uses `AutocompleteInteraction`, and `ModalInteractionCreateEvent` uses `ModalInteraction`. When an interaction-create event is deserialized, the returned event must correspond to the kind of the deserialized interaction.
